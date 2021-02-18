$oneolcom
!! Turns on end-of-line comments using !!. The rest of the line after !! is interpreted as a comment.

!! The basic sets over which most variables will be defined.
set SLICE / winterday, winternight, summerday, summernight, otherday, othernight /;
set PLANT / woodHP, wasteHP, oilHP, heatpump, gasCHP /;
set FUEL / wood, waste, oil, gas, elec /;

!! Now let's input data for a bunch of parameters. This could have been written much more compactly
!! in table format or by importing from Excel, but the GAMS syntax would have become much uglier and
!! harder to read.

parameter days_per_slice(SLICE) /
    winterday       122
    winternight     122
    summerday       122
    summernight     122
    otherday        121
    othernight      121
/;

parameter hours_per_day(SLICE) /
    winterday       16
    winternight     8
    summerday       16
    summernight     8
    otherday        16
    othernight      8
/;

!! Here is an example of a parameter that gets its value by a calculation.
parameter hours(SLICE);
hours(SLICE) = days_per_slice(SLICE) * hours_per_day(SLICE);

!! coefficient of performance = heat out / elec in
parameter heatpumpCOP(SLICE) /
    winterday       4
    winternight     4
    summerday       5
    summernight     5
    otherday        4.5
    othernight      4.5
/;

!! kr/MWh
parameter elecprice(SLICE) /
    winterday       600
    winternight     450
    summerday       350
    summernight     250
    otherday        450
    othernight      350
/;

!! MW (average demand per time slice)
parameter heatdemand(SLICE) /
    winterday       900
    winternight     900
    summerday       150
    summernight     150
    otherday        450
    othernight      550
/;

!! MW heat
parameter startcapac(PLANT) /
    woodHP      100
    wasteHP     120
    oilHP       300
    heatpump    220
    gasCHP      300
/;

!! total system efficiency, including both heat and power out
!! heat pump uses heatpumpCOP parameter instead
parameter efficiency(PLANT) /
    woodHP      0.9
    wasteHP     0.9
    oilHP       0.9
    heatpump    0
    gasCHP      0.9
/;

!! "alpha value" for a CHP = power out / heat out
parameter powerheatratio(PLANT) /
    gasCHP      1
/;

!! kr/MWh
parameter fuelprice(FUEL) /
    wood    220
    waste   0
    oil     550
    gas     300
    elec    0
/;

!! g CO2 / kWh fuel (or kg/MWh or tons/GWh)
parameter emissionsCO2(FUEL) /
    wood    0
    waste   90
    oil     266
    gas     202
    elec    250
/;

!! In GAMS, parameters that are declared using the 'parameter' syntax can be indexed over sets and
!! can be redefined. You can also declare parameters using the 'scalar' syntax in order to define
!! simple constants that cannot be redefined.

scalar lifetime / 25 /;             !! years of economic lifetime for discounting
scalar discountrate / 0.05 /;

scalar annualwaste / 400000 /;      !! tons of waste/year
scalar wasteheatcontent / 2.8 /;    !! MWh heat/ton solid waste

parameter CRF;                      !! capital recovery factor (for annualization of investment costs)
CRF = discountrate / (1 - 1/(1+discountrate)**lifetime);
!! Unfortunately scalars cannot be calculated, hench the use of the parameter syntax for CRF.




!! Now we'll define the variables: some are restricted to be >= 0 and others are free.
!! The objective function must be a free variable.

variable Systemcost;                !! Mkr/year
variable CO2emissions;              !! Mton CO2/year
variable FuelUse(FUEL,SLICE);       !! GWh fuel/slice

positive variable HeatProduction(PLANT,SLICE);      !! GWh heat/slice

variable MaxHeatProduction(PLANT,SLICE);            !! GWh heat/slice (output variable only, not required in the model)
variable RunningCosts(PLANT,SLICE);                 !! kr/MWh (output variable only, not required in the model)

!! Also note the notational convention I use: all parameters begin with a small letter and all variables
!! begin with a capital letter. The consistent use of conventions like this make it MUCH easier to
!! understand the equations of an optimization model - for other people or for yourself when you revisit
!! the model some years after originally coding it. This is probably the single best practical tip I have
!! for you, so don't forget it!!




!! The last part of the model are the constraints. They must first be declared using the 'equation'
!! syntax before the actual math is specified.

equation Capacity(PLANT,SLICE);
equation Demand(SLICE);
equation Calculate_FuelUse(FUEL,SLICE);
equation TotalCO2;
equation Wastelimit_winter;
equation Wastelimit_summer;
equation Wastelimit_other;
equation Totalcosts;

equation Calculate_MaxHeat(PLANT,SLICE);        !! only for output, not required in the model
equation Calculate_RunningCosts(PLANT,SLICE);   !! only for output, not required in the model



!! Below is the math of the constraints. Incredibly, GAMS doesn't allow the natural '=', '>=' and
!! '<=' symbols. These must be writted as '=E=', '=G=' and '=L='. I hate GAMS with a passion.

!! Heat output per plant limited by installed capacity, divide by 1000 to get GWh
!! All plants are assumed to have 100% availability in this model.
Capacity(PLANT,SLICE)..
    HeatProduction(PLANT,SLICE) =L= startcapac(PLANT) * hours(SLICE) / 1000;

!! Must satisfy heat demand each slice.
Demand(SLICE)..
    sum(PLANT, HeatProduction(PLANT,SLICE)) =G= heatdemand(SLICE) * hours(SLICE) / 1000;

!! Make a variable that accounts for all fuel use per slice (electricity is also a fuel here).
!! Here is one way of using the powerful but horribly ugly '$-syntax' in GAMS. The dollar is usually
!! read as 'if' or 'such that'. For example:
!! expression X $ sameas(FUEL,oil)    means    if FUEL == "oil" then expression X
Calculate_FuelUse(FUEL,SLICE)..
    FuelUse(FUEL,SLICE) =E=
        (HeatProduction('oilHP',SLICE) / efficiency('oilHP'))
                $ sameas(FUEL,'oil')
        + (HeatProduction('wasteHP',SLICE) / efficiency('wasteHP'))
                $ sameas(FUEL,'waste')
        + (HeatProduction('gasCHP',SLICE) * (1+powerheatratio('gasCHP')) / efficiency('gasCHP'))
                $ sameas(FUEL,'gas')
        + (HeatProduction('woodHP',SLICE) / efficiency('woodHP'))
                $ sameas(FUEL,'wood')
        + (HeatProduction('heatpump',SLICE) / heatpumpCOP(SLICE))
                $ sameas(FUEL,'elec')
        - (HeatProduction('gasCHP',SLICE) * powerheatratio('gasCHP'))
                $ sameas(FUEL,'elec')
    ;

!! Divide by 1e6 to get Mton CO2.
TotalCO2..
    CO2emissions =E= sum((FUEL,SLICE), FuelUse(FUEL,SLICE) * emissionsCO2(FUEL)) / 1e6;

Wastelimit_winter..
    FuelUse('waste','winterday') + FuelUse('waste','winternight')
            =E= annualwaste * wasteheatcontent * (hours('winterday') + hours('winternight'))/8760/1000;

Wastelimit_summer..
    FuelUse('waste','summerday') + FuelUse('waste','summernight')
             =E= annualwaste * wasteheatcontent * (hours('summerday') + hours('summernight'))/8760/1000;

Wastelimit_other..
    FuelUse('waste','otherday') + FuelUse('waste','othernight')
            =E= annualwaste * wasteheatcontent * (hours('otherday') + hours('othernight'))/8760/1000;

!! Add up total fuel + annualized investment costs.  Mkr
Totalcosts..
    Systemcost =E= 1/1000 * (
        sum((FUEL,SLICE), FuelUse(FUEL,SLICE) * fuelprice(FUEL))        !! electricity costs zero in fuelprice()
        + sum(SLICE, FuelUse('elec',SLICE) * elecprice(SLICE))          !! ... and is accounted for here instead
    );



!! Calculate an interesting output variable, not required in the model.
Calculate_MaxHeat(PLANT,SLICE)..
    MaxHeatProduction(PLANT,SLICE) =E= startcapac(PLANT) * hours(SLICE) / 1000;

!! Calculate an interesting output variable, not required in the model.
Calculate_RunningCosts(PLANT,SLICE)..
    RunningCosts(PLANT,SLICE) =E=
        (fuelprice('oil') / efficiency('oilHP'))
                $ sameas(PLANT,'oilHP')
        + (fuelprice('waste') / efficiency('wasteHP'))
                $ sameas(PLANT,'wasteHP')
        + (fuelprice('gas') * (1+powerheatratio('gasCHP')) / efficiency('gasCHP') - elecprice(SLICE) * powerheatratio('gasCHP'))
                $ sameas(PLANT,'gasCHP')
        + (fuelprice('wood') / efficiency('woodHP'))
                $ sameas(PLANT,'woodHP')
        + (elecprice(SLICE) / heatpumpCOP(SLICE))
                $ sameas(PLANT,'heatpump')
;




!! Some weird statements to reduce the size of the .LST file which logs the output. Without these lines,
!! that file can become HUGE. But changing these lines can be useful when advanced model debugging is
!! needed (especially to find infeasibilities).
option limrow = 0;
option limcol = 0;
option solprint = off;
!! Put the next line at the top of the file to suppress listing the entire model in the .LST file.
!! However, note that this is where error diagnostics will appear if your model has errors.
$offlisting

!! Use ALL of the defined constraints in the model. Alternatively we could have listed them individually.
model LPtown /all/;
!!LPtown.OptFile = 1;         !! uncomment to make GAMS read cplex.opt to set solver options



!!!!!!!!!! Model formulation: identify parameters and variables, useful sets, constraints and objective.


!! Now we can run the model and print some basic output. Note that suffixes are required for variables
!! and constraints. The command 'display variablename.L' prints the current (hopefully optimal) variable
!! value (read as "level"). The command 'display constraintname.M' prints the marginal cost (i.e. shadow
!! price) of that constraint.

!! Another interesting option that we won't use here:
!! The command 'display variablename.M' prints the reduced cost of the variable (i.e. the amount that
!! the objective coefficient of INACTIVE variables must change for them to enter the optimal solution).
!! (useful for seeing which unused technologies are almost competitive)

!! Base case variable limits
!! Use the suffix .fx to fix a variable at some value, or .lo and .up to set lower and upper bounds.
CO2emissions.up = inf;              !! no upper limit on CO2.

solve LPtown using LP minimizing Systemcost;
display '################################## Item 4: Base case, no investments ##################################';
display Systemcost.l, HeatProduction.l, Capacity.m, Demand.m, CO2emissions.l, TotalCO2.m, MaxHeatProduction.l, RunningCosts.l;
display Wastelimit_winter.m, Wastelimit_summer.m, Wastelimit_other.m;
display '---------------------------------------------------------------------------';
!! Base case: understand the results, active & inactive constraints and their shadow prices


!!!!!!!!!! Some useful GAMS syntax
$ontext     !! start a block comment

!! GAMS parameter reassignments

param1 = 1;                 !! modify a scalar parameter
param2('solarPV') = 2;      !! modify a parameter
param3(TECH) = 2 * param3(TECH);    !! double a parameter for all set values

!! modifying GAMS variable bounds

MyVariable1.fx = 23;    !! fix a variable

MyVariable1.lo = 23;    !! .fx is equivalent to setting both .lo and .up
MyVariable1.up = 23;

MyVariable1.lo = 0;     !! remove the bounds for a positive variable
MyVariable1.up = inf;

MyVariable3.fx('wind', 2050) = 0;   !! fix a variable that is indexed over sets
MyVariable3.fx(TECH, TIME) = 0;     !! fix a variable that is indexed over sets

$offtext     !! end a block comment
