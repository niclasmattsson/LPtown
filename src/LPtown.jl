module LPtown

using JuMP, Clp, PrettyTables

export makeparameters, makevariables, makeconstraints, makemodel, runmodel, printtable

function makeparameters()
    # index sets
    SLICE = [:winterday, :winternight, :summerday, :summernight, :otherday, :othernight]
    PLANT = [:woodHP, :wasteHP, :oilHP, :heatpump, :gasCHP, :woodCHP]
    FUEL  = [:wood, :waste, :oil, :gas, :elec]

    # parameters(SLICE)
    sliceparameters = [
    #                 winter  winter  summer  summer  other   other
    #                   day   night     day   night     day   night
    :days_per_slice     122     122     122     122     121     121
    :hours_per_day       16       8      16       8      16       8
    :heatpumpCOP          4       4       5       5     4.5     4.5
    :elecprice          600     450     350     250     450     350    # kr/MWh
    :heatdemand         900     900     150     150     450     550    # MW (average demand per slice)
    ]
    days_per_slice, hours_per_day, heatpumpCOP, elecprice, heatdemand =
        readtable(sliceparameters, SLICE)
    hours = Dict(s => days_per_slice[s]*hours_per_day[s] for s in SLICE)

    # parameters(PLANT)
    plantparameters = [
    #              woodHP   wasteHP   oilHP  heatpump  gasCHP  woodCHP
    :startcapac      100      120      300      220      300        0      # MW heat
    :efficiency      0.9      0.9      0.9        0      0.9      0.9      # total system efficiency incl. heat and power out
                                                                           # (heat pump uses heatpumpCOP parameter instead)
    :powerheatratio    0        0        0        0        1      0.3      # "alpha value" for a CHP = power out / heat out
    :investcost        0        0        0        0     6500     3600      # kr/kW heat
    ]
    startcapac, efficiency, powerheatratio, investcost =
        readtable(plantparameters, PLANT)

    # parameters(FUEL)
    fuelparameters = [
    #              wood   waste    oil     gas    elec
    :fuelprice      220      0     550     300       0     # kr/MWh
    :emissionsCO2     0     90     266     202     250     # g CO2 / kWh fuel (or kg/MWh or tons/GWh)
    ]
    fuelprice, emissionsCO2 = readtable(fuelparameters, FUEL)

    lifetime = 25            # years of economic lifetime for discounting
    discountrate = 0.05
    wasteheatcontent = 2.8   # MWh heat/ton solid waste
    annualwaste = 400000     # tons of waste/year

    # capital recovery factor (for annualization of investment costs)
    CRF = discountrate / (1 - 1/(1+discountrate)^lifetime)

    # new NamedTuple syntax in Julia 1.5: https://github.com/JuliaLang/julia/pull/34331
    # (so functions that are passed parameter objects are type stable)
    return (; SLICE, PLANT, FUEL, heatpumpCOP, elecprice, heatdemand, hours,
        startcapac, efficiency, powerheatratio, investcost, fuelprice, emissionsCO2,
        lifetime, discountrate, wasteheatcontent, annualwaste, CRF)
end

function makevariables(model, params)
    (; SLICE, PLANT, FUEL) = params

    @variables model begin
        Systemcost                      # Mkr/year
        CO2emissions                    # Mton CO2/year
        FuelUse[f in FUEL, s in SLICE]  # GWh fuel/slice
        Totalwaste                      # tons of waste/year

        HeatProduction[p in PLANT, s in SLICE] >= 0  # GWh heat/slice
        Invest[p in PLANT] >= 0                      # MW heat
    end

    return (; Systemcost, CO2emissions, FuelUse, Totalwaste, HeatProduction, Invest)
end

function makeconstraints(model, vars, params)
    (; SLICE, PLANT, FUEL, heatpumpCOP, elecprice, heatdemand, hours,
        startcapac, efficiency, powerheatratio, investcost, fuelprice, emissionsCO2,
        lifetime, discountrate, wasteheatcontent, annualwaste, CRF) = params
    (; Systemcost, CO2emissions, FuelUse, Totalwaste, HeatProduction, Invest) = vars

    @constraints model begin
        # Heat output per plant limited by installed capacity, divide by 1000 to get GWh
        # All plants are assumed to have 100% availability in this model.
        Capacity[p in PLANT, s in SLICE],
            HeatProduction[p,s] <= (startcapac[p] + Invest[p]) * hours[s] / 1000

        # Must satisfy heat demand each slice.
        Demand[s in SLICE],
            sum(HeatProduction[p,s] for p in PLANT) >= heatdemand[s] * hours[s] / 1000

        # No investments in plants with zero investment costs
        NoInvest[p in PLANT; investcost[p] == 0],
            Invest[p] == 0

        # Make a variable that accounts for all fuel use per slice (electricity is also a fuel here).
        Calculate_FuelUse[f in FUEL, s in SLICE],
            FuelUse[f,s] == (
                (f == :oil) ? HeatProduction[:oilHP,s] / efficiency[:oilHP] :
                (f == :waste) ? HeatProduction[:wasteHP,s] / efficiency[:wasteHP] :
                (f == :gas) ? HeatProduction[:gasCHP,s] * (1+powerheatratio[:gasCHP]) / efficiency[:gasCHP] :
                (f == :wood) ? HeatProduction[:woodHP,s] / efficiency[:woodHP] +
                                + HeatProduction[:woodCHP,s] * (1+powerheatratio[:woodCHP]) / efficiency[:woodCHP] :
                (f == :elec) ? HeatProduction[:heatpump,s] / heatpumpCOP[s] +
                                - HeatProduction[:gasCHP,s] * powerheatratio[:gasCHP] +
                                - HeatProduction[:woodCHP,s] * powerheatratio[:woodCHP]
                : 0.0
            )

        # Divide by 1e6 to get Mton CO2.
        TotalCO2,
            CO2emissions == sum(FuelUse[f,s] * emissionsCO2[f] for f in FUEL, s in SLICE) / 1e6

        Wastelimit_annual,
            Totalwaste <= annualwaste

        Wastelimit_winter,
            FuelUse[:waste,:winterday] + FuelUse[:waste,:winternight] ==
                Totalwaste * wasteheatcontent * (hours[:winterday] + hours[:winternight])/8760/1000

        Wastelimit_summer,
            FuelUse[:waste,:summerday] + FuelUse[:waste,:summernight] ==
                Totalwaste * wasteheatcontent * (hours[:summerday] + hours[:summernight])/8760/1000

        Wastelimit_other,
            FuelUse[:waste,:otherday] + FuelUse[:waste,:othernight] ==
                Totalwaste * wasteheatcontent * (hours[:otherday] + hours[:othernight])/8760/1000

        Totalcosts,
            Systemcost == 1/1000 * (
                sum(FuelUse[f,s] * fuelprice[f] for f in FUEL, s in SLICE) +   # electricity costs zero in fuelprice()
                + sum(FuelUse[:elec,s] * elecprice[s] for s in SLICE) +         # ... and is accounted for here instead
                + sum(Invest[p] * investcost[p] * CRF for p in PLANT)
            )
    end   #constraints

    return (; Capacity, Demand, NoInvest, Calculate_FuelUse, TotalCO2, Totalcosts,
        Wastelimit_annual, Wastelimit_winter, Wastelimit_summer, Wastelimit_other)
end

function makemodel()
    model = Model(Clp.Optimizer)
    #model = Model(with_optimizer(GLPKSolverLP, print_level=0))

    params = makeparameters()
    vars = makevariables(model, params)
    constraints = makeconstraints(model, vars, params)

    (; Systemcost) = vars

    @objective model Min begin
        Systemcost
    end

    return model, params, vars, constraints
end

function runmodel()
    LPtown, params, vars, constraints = makemodel()

    (; PLANT) = params
    (; Systemcost, CO2emissions, FuelUse, Totalwaste, HeatProduction, Invest) = vars
    (; Demand, Capacity) = constraints

    # Some optional additional constraints:
    # [set_upper_bound(Invest[p], 0) for p in PLANT]  # no investments allowed
    # set_upper_bound(CO2emissions, 0)                # carbon neutral

    optimize!(LPtown)

    printtable(value.(Invest), "Invest", ["[MW]"])
    printtable(1000*dual.(Demand), "Shadow price Demand", ["[kr/MWh]"])
    printtable(1000*dual.(Capacity), "Shadow price Capacity", "[kr/MWh]")
    printtable(value.(HeatProduction), "HeatProduction", "[GWh]")
    printtable(1000*reduced_cost.(HeatProduction), "Reduced cost HeatProduction", "[kr/MWh]")

    println("\n\nSolve status: ", termination_status(LPtown))
    println("\nObjective [Mkr]: ", objective_value(LPtown))
    println("CO2emissions [Mton CO2/year]: ", value(CO2emissions))
    println("Reduced costs CO2emissions [kr/ton CO2]: ", reduced_cost(CO2emissions))

    return nothing
end

# helper functions for reading the data tables
readrow(table, rownum, headings) = Dict(h => table[rownum, i+1] for (i, h) in enumerate(headings))
readtable(table, headings) = Tuple(readrow(table, i, headings) for i = 1:size(table,1))

# helper functions for printing output tables
const DenseAxisArray = JuMP.Containers.DenseAxisArray
printtable(x::DenseAxisArray, tabletitle, header) =
    pretty_table(x.data; header, row_labels=x.axes[1], row_label_column_title=tabletitle)
printtable(x::DenseAxisArray{Float64,2}, varname, unit) =
    pretty_table(x.data; header=(x.axes[2], fill(unit, size(x,2))), row_labels=x.axes[1], row_label_column_title=varname)

end # module
