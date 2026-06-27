%% WRO 2026 Future Engineers -- Power Consumption / Electrical Budget Model (MATLAB)
% =========================================================================
% DBTL CONTEXT
% -------------------------------------------------------------------------
% This script is the "DESIGN" phase artifact for the ELECTRICAL-SYSTEM DBTL
% cycle. It models the complete power-distribution network of the car, computes
% total current draw and power consumption per rail, verifies every regulator/
% converter is operated within its safe current rating, and predicts 2S LiPo
% battery runtime for a full competition day (practice runs + heats).
%
% It is a SEPARATE model from the lap-time optimisation script
% (wro2026_laptime_optimisation.m). It does NOT redo the mechanical/gearing
% optimisation -- it CONSUMES one output from it (the drivetrain operating
% point: motor run current and the duty cycle of a competition run) as a fixed
% input, and asks: does the electrical system deliver it safely, and for how
% long can the battery sustain it?
%
% Its outputs (per-rail current budget, runtime estimate, per-regulator margin,
% power-budget.mat) feed the "TEST" phase, where the team bench-measures actual
% current draw with a multimeter / USB power meter and compares against these
% predictions, and a future combined Simscape Electrical model of the vehicle.
%
% MODELLING SIMPLIFICATIONS (stated explicitly, as required):
%   * Common GND is modelled as a SINGLE ideal reference node. Ground-loop
%     resistance and noise are NOT modelled in this version.
%   * Battery voltage is held FLAT at 7.4 V nominal (no voltage sag, no
%     internal-resistance droop, no capacity-vs-discharge-rate non-linearity).
%     The constant-current discharge model this implies makes the runtime
%     estimate slightly OPTIMISTIC versus a real sagging LiPo, not pessimistic.
%     A C-rating margin check (Section 4.1) flags when this flat-voltage
%     assumption is most likely to break down.
%   * The ESP32 3.3 V rail (ToF + IMU) is folded into the ESP32 VIN current at
%     the 5 V level to avoid double-counting -- see Section 3.5 comment.
%
% COMPATIBILITY: MATLAB R2020a+ recommended (exportgraphics, heatmap). The
% script auto-falls back to print()/imagesc on older MATLAB and on Octave so
% the numerical model and logs are always produced.
% =========================================================================

clear; clc; close all;

%% =====================================================================
%% SECTION 2 -- FIXED PARAMETERS BLOCK (organised by subsystem)
%% ---------------------------------------------------------------------
%% Comment tag convention (grep-able):
%%   [DATASHEET] value taken from a component datasheet
%%   [MEASURED]  value bench-measured for this build
%%   [ESTIMATE]  engineering estimate, replace with datasheet/bench value
%%   [CONFIRM]   placeholder carried from project notes, MUST be verified
%% No magic numbers live inside the calculation functions -- every constant is
%% defined here in the struct `p` and passed in.
%% =====================================================================
p = struct();

% --- Battery (2S LiPo) ---------------------------------------------------
p.battery_chemistry                  = '2S LiPo';
p.battery_voltage_nom_V              = 7.4;    % [DATASHEET] 2S nominal; flat busbar voltage used throughout
p.battery_capacity_mAh               = 300;    % [CONFIRM] carried from prior notes; UPDATE if a different pack is fitted
p.battery_capacity_Ah                = p.battery_capacity_mAh / 1000;
p.battery_max_continuous_discharge_C = 20;     % [CONFIRM] typical small 2S C-rating; VERIFY against pack label

% --- N20 drive motor (via TB6612FNG) ------------------------------------
p.n20_stall_current_A      = 1.5;   % [CONFIRM] placeholder for small N20 at ~7.4V; worst case the driver must survive
p.n20_typical_run_current_A= 0.35;  % [ESTIMATE] running current under normal load at operating RPM; refine by current clamp
p.n20_duty_cycle           = 0.85;  % [ESTIMATE] fraction of a run spent driving (vs idle/coasting/stopped)

% --- TB6612FNG motor driver ---------------------------------------------
p.tb6612_max_continuous_A_per_channel = 1.2;        % [DATASHEET] 1.2 A continuous per channel
p.tb6612_peak_A_per_channel           = 3.2;        % [DATASHEET] 3.2 A peak (single 10 ms pulse)
p.tb6612_vm_range_V                   = [2.5 13.5]; % [DATASHEET] recommended motor supply range (7.4V is comfortably inside)
p.tb6612_quiescent_current_A          = 0.002;      % [DATASHEET] logic-side draw, negligible, kept for completeness

% --- KOOBOOK boost converter (7.4V -> 12V) ------------------------------
p.boost_converter_input_V    = p.battery_voltage_nom_V;
p.boost_converter_output_V   = 12.0;  % [DATASHEET] boosted rail voltage
p.boost_converter_efficiency = 0.85;  % [ESTIMATE] small boost module; boosts are LESS efficient than equivalent bucks
p.boost_converter_max_output_A = 1.0; % [CONFIRM] KOOBOOK module spec; most small boosts are 0.5-1.5 A out

% --- Delta BFB0312HA-C blower fan (12V rail) ----------------------------
p.fan_rated_voltage_V        = 12.0;  % [DATASHEET]
p.fan_rated_current_A        = 0.07;  % [DATASHEET] typical
p.fan_max_current_A          = 0.11;  % [DATASHEET] max (NOT a transient peak per datasheet note)
p.fan_safety_label_current_A = 0.20;  % [DATASHEET] safety/label current; absolute upper sanity bound only, not design current
p.fan_rated_power_W          = 0.84;  % [DATASHEET] rated power
p.fan_rated_rpm              = 7500;  % [DATASHEET]

% --- 5V buck converter (7.4V -> 5V) -------------------------------------
p.buck_converter_input_V    = p.battery_voltage_nom_V;
p.buck_converter_output_V   = 5.0;   % [DATASHEET] regulated bus voltage
p.buck_converter_efficiency = 0.92;  % [ESTIMATE] small synchronous buck; replace with datasheet/bench value
p.buck_converter_rated_A    = 3.0;   % [CONFIRM] wiring spec "rated for 3A+"; conservative rated figure

% --- Raspberry Pi Zero 2W (5V rail) -------------------------------------
p.rpi_idle_current_A    = 0.15;  % [ESTIMATE] idle/light-load at 5V
p.rpi_typical_current_A = 0.35;  % [ESTIMATE] moderate CPU load (camera processing)
p.rpi_peak_current_A    = 0.70;  % [ESTIMATE] heavy CPU spike (the "computing spike" the 3A+ buck absorbs)
% Three-state load -> explicit duty fractions that MUST sum to 1.0 (guarded below)
p.rpi_duty = struct('idle', 0.20, 'typical', 0.70, 'peak', 0.10);  % [ESTIMATE]
assert(abs(sum(struct2array_compat(p.rpi_duty)) - 1.0) < 1e-6, ...
       'RPi duty fractions must sum to 1');

% --- MG90S / AGFRC steering servo (5V rail) -----------------------------
p.servo_idle_current_A    = 0.01;  % [ESTIMATE] holding position, minimal load
p.servo_typical_current_A = 0.10;  % [ESTIMATE] actively turning, light load
p.servo_stall_current_A   = 0.80;  % [CONFIRM] stall (mechanically blocked); worst-case bound only
p.servo_active_duty_cycle = 0.30;  % [ESTIMATE] fraction of run actively steering (vs holding centred)

% --- Arduino Nano ESP32 (powered via VIN from 5V bus) -------------------
% NOTE: these currents are measured AT THE 5V VIN PIN and already INCLUDE the
% ESP32 internal 5V->3.3V regulator and everything it then feeds (ToF + IMU).
% See Section 3.5 -- the 3.3V loads are NOT separately added to the 5V bus.
p.esp32_typical_current_A = 0.08;  % [ESTIMATE] VIN current, WiFi/BT off/light, control loop running (incl. 3.3V rail)
p.esp32_peak_current_A    = 0.18;  % [ESTIMATE] VIN peak with WiFi/BT or compute spikes (incl. 3.3V rail)
p.esp32_peak_duty_cycle   = 0.05;  % [ESTIMATE]
p.esp32_internal_3v3_efficiency = 0.85;  % [ESTIMATE] assumed ESP32 LDO/buck eff; folded into VIN figures above (informational)

% --- VL53L1X ToF sensors (3.3V rail, downstream of ESP32 regulator) -----
p.tof_count              = 2;      % [CONFIRM] actual number of ToF sensors
p.tof_current_per_unit_A = 0.020;  % [DATASHEET] typical active ranging current
p.tof_duty_cycle         = 1.0;    % [ESTIMATE] assume continuously ranging through a run

% --- MPU6050 IMU (3.3V rail, downstream of ESP32 regulator) -------------
p.imu_current_A  = 0.004;  % [DATASHEET] typical active current
p.imu_duty_cycle = 1.0;    % [ESTIMATE] continuously sampling through a run

% --- Runtime / discharge model -----------------------------------------
p.usable_capacity_fraction = 0.80;  % [ESTIMATE] safe LiPo discharge fraction (~3.3-3.5 V/cell stop)

% --- Competition-day schedule (Section 6.1) -----------------------------
p.n_runs_practice    = 8;    % [CONFIRM] placeholder schedule
p.n_runs_competition = 4;    % [CONFIRM] placeholder schedule
p.run_duration_s     = 15;   % [DATASHEET] from lap-time optimisation script target (15 s run)
p.idle_between_runs_s= 180;  % [CONFIRM] typical time between runs; electronics may stay powered
p.idle_electronics_fraction = 0.5;  % [ESTIMATE] fraction of 5V-rail avg current drawn between runs (sleep vs stay-on)

% --- Operating point CONSUMED from the lap-time optimisation model ------
% This model does NOT redo the lap-time prediction; it imports it. Preferred
% source is optimal_design.mat (written by wro2026_laptime_optimisation.m),
% which carries the predicted run time, lap count and wheel RPM. If that file
% is not on the path, the fallbacks below are used and flagged as an assumption.
p.opt_design_file     = 'optimal_design.mat';  % produced by the lap-time script
p.run_time_s_fallback = p.run_duration_s;      % [CONFIRM] full-RUN time (all laps) if .mat absent
p.n_laps_fallback     = 3;                      % [CONFIRM] laps per run (WRO open round)
p.lap_distance_m      = 7.15;                   % [ESTIMATE] mid-lane lap length (from lap-time model)

% --- Battery voltage-sag (state-of-charge) model -----------------------
% OPTIONAL sag-aware extension (Section 6.3). The rest of the budget holds the
% bus flat at 7.4 V; here we model how terminal voltage falls with state of
% charge (SoC) and under load, and feed that voltage into the lap-time
% optimisation model (assumed uploaded alongside this script) to predict how
% the lap time lengthens as the pack drains. Not used by Sections 3-6.2.
p.battery_series_cells            = 2;     % [DATASHEET] 2S
p.battery_internal_resistance_ohm = 0.12;  % [ESTIMATE] 2S pack internal resistance (terminal sag = I*R)
p.soc_plot_min_pct                = 0;     % lowest SoC plotted (%)
% Typical LiPo open-circuit voltage per cell vs SoC (resting, no load):
p.lipo_soc_breakpoints_pct = [100  90   80   70   60   50   40   30   20   10   0];   % [DATASHEET] typical
p.lipo_ocv_per_cell_V      = [4.20 4.06 3.95 3.87 3.80 3.75 3.70 3.65 3.55 3.42 3.30];% [DATASHEET] typical LiPo

% --- Sensitivity sweep grids (Section 5) --------------------------------
p.boost_eff_sweep = [0.75 0.85 0.92];  % pessimistic / nominal / optimistic
p.buck_eff_sweep  = [0.85 0.92 0.96];  % pessimistic / nominal / optimistic

% --- Safety-margin warning thresholds (used for OK/WARNING flags) -------
p.thr_tb6612_continuous = 1.5;
p.thr_tb6612_stall      = 1.0;
p.thr_buck_peak         = 1.3;
p.thr_boost_margin      = 1.3;
p.thr_battery_C         = 2.0;

%% ---------------------------------------------------------------------
%% SECTION 1 -- SYSTEM ARCHITECTURE AS AN EXPLICIT DATA STRUCTURE
%% ---------------------------------------------------------------------
%% Each load is one entry of a struct array. `levels_A` are the discrete
%% current states and `duty` the time-fraction at each state (duty sums to 1,
%% structurally enforced by avg_load_current()). `peak_A` is the worst-case
%% instantaneous current used for regulator survival checks. This single
%% structure drives the per-rail calculations, the Section 5 sweeps and the
%% Section 6 runtime model -- it is NOT re-encoded as ad-hoc variables.
p.loads = build_topology(p);

%% =====================================================================
%% SECTION 3 + 4 -- PER-RAIL BUDGET AT NOMINAL EFFICIENCIES
%% (all per-rail maths live in compute_power_budget(); the power-balance
%%  assertion in Section 4 runs automatically inside that function)
%% =====================================================================
r = compute_power_budget(p, p.boost_converter_efficiency, p.buck_converter_efficiency);

% --- Section 3.6 / 4: safety margins (computed once on the nominal result) ---
r.tb6612_margin       = p.tb6612_max_continuous_A_per_channel / p.n20_typical_run_current_A;
r.tb6612_stall_margin = p.tb6612_peak_A_per_channel / p.n20_stall_current_A;
r.boost_margin        = p.boost_converter_max_output_A / r.fan_current_12V_A;

% --- Section 4.1: battery C-rating check ---
r.max_safe_discharge_current_A = p.battery_capacity_Ah * p.battery_max_continuous_discharge_C;
r.battery_current_margin       = r.max_safe_discharge_current_A / r.total_battery_current_A;

%% =====================================================================
%% SECTION 5 -- SENSITIVITY SWEEP (3x3 efficiency grid)
%% =====================================================================
nB = numel(p.boost_eff_sweep);
nK = numel(p.buck_eff_sweep);
sweep_current  = zeros(nB, nK);   % rows = boost eff, cols = buck eff
sweep_runtime  = zeros(nB, nK);   % usable runtime (min)
for ib = 1:nB
    for ik = 1:nK
        rs = compute_power_budget(p, p.boost_eff_sweep(ib), p.buck_eff_sweep(ik));
        sweep_current(ib, ik) = rs.total_battery_current_A;
        sweep_runtime(ib, ik) = rs.usable_runtime_minutes;
    end
end
% Worst case = highest current = shortest runtime (pessimistic both converters)
[worst_runtime_min, idx_worst] = min(sweep_runtime(:));
[iwB, iwK] = ind2sub(size(sweep_runtime), idx_worst);
worst_boost_eff = p.boost_eff_sweep(iwB);
worst_buck_eff  = p.buck_eff_sweep(iwK);
worst_current_A = sweep_current(iwB, iwK);

%% =====================================================================
%% SECTION 6.1 -- COMPETITION-DAY CHARGE BUDGET
%% =====================================================================
cd_total_runs       = p.n_runs_practice + p.n_runs_competition;
cd_active_time_s    = cd_total_runs * p.run_duration_s;
cd_idle_time_s      = max(cd_total_runs - 1, 0) * p.idle_between_runs_s;   % gaps between runs
% Between runs: motor + fan off, electronics drop to a lower idle state.
cd_idle_current_A   = r.total_5V_avg_current_A * p.idle_electronics_fraction;  % [ESTIMATE] see idle_electronics_fraction
cd_charge_used_Ah   = (r.total_battery_current_A * cd_active_time_s + ...
                       cd_idle_current_A * cd_idle_time_s) / 3600;
cd_usable_capacity_Ah = p.battery_capacity_Ah * p.usable_capacity_fraction;
cd_charge_margin    = cd_usable_capacity_Ah / cd_charge_used_Ah;
% Equivalent "required continuous runtime" for the day (active-driving time only),
% used purely for the Figure 3 visual gap-to-requirement comparison.
cd_required_runtime_min = cd_active_time_s / 60;

%% =====================================================================
%% SECTION 6.2 -- PER-LAP POWER DEPLETION & LAP-TIME PREDICTION
%% ---------------------------------------------------------------------
%% Assuming the pack starts FULLY CHARGED, predict how much charge/energy each
%% lap costs and how the state-of-charge (SoC) declines lap by lap. The lap
%% time itself is NOT computed here -- it is the operating point IMPORTED from
%% the lap-time optimisation model (optimal_design.mat), so the per-lap
%% depletion is explicitly CORRELATED with the predicted lap time
%% (energy per lap = battery power x lap time).
%% ---------------------------------------------------------------------
op = load_operating_point(p);          % predicted lap time / laps (consumed input)
lap = compute_lap_depletion(p, r, op); % per-lap charge/energy + SoC schedule

%% =====================================================================
%% SECTION 6.3 -- VOLTAGE SAG vs STATE OF CHARGE, AND ITS EFFECT ON LAP TIME
%% (sag-aware extension; feeds terminal voltage into the lap-time model)
%% =====================================================================
sag = compute_soc_voltage_laptime(p, r, op);

%% =====================================================================
%% SECTION 7.1 -- CONSOLE SUMMARY + LOG FILE
%% =====================================================================
log_lines = {};
emit = @(s) fprintf('%s\n', s);   % console
rec  = @(s) s;                    % collected below via local append

% Build the report as a cell array of lines, then print + log together.
L = {};
L{end+1} = '=========================================================';
L{end+1} = ' WRO 2026 POWER CONSUMPTION MODEL -- DESIGN-PHASE REPORT';
L{end+1} = sprintf(' Generated: %s', datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
L{end+1} = '=========================================================';
L{end+1} = '';

% --- Assumptions requiring verification (auto-generated from flags) ---
L{end+1} = '=== ASSUMPTIONS REQUIRING VERIFICATION ===';
av = assumptions_to_verify(p);
for k = 1:numel(av)
    L{end+1} = sprintf('  [%s] %-28s = %-10s  %s', ...
        av(k).tag, av(k).name, av(k).value, av(k).note); %#ok<AGROW>
end
L{end+1} = '';

% --- Per-rail current budget ---
L{end+1} = '=== PER-RAIL CURRENT BUDGET ===';
L{end+1} = sprintf('12V rail (fan):              %6.3f A  (from 7.4V battery: %6.3f A after boost loss)', ...
                   r.fan_current_12V_A, r.boost_input_current_A);
L{end+1} = sprintf('5V rail (RPi+servo+ESP32):   %6.3f A  (from 7.4V battery: %6.3f A after buck loss)', ...
                   r.total_5V_avg_current_A, r.buck_input_current_A);
L{end+1} = sprintf('7.4V direct (N20 motor):     %6.3f A', r.n20_avg_current_A);
L{end+1} = sprintf('  (3.3V logic rail ToF+IMU:  %6.3f A -- folded into ESP32 VIN, NOT added again)', ...
                   r.total_3V3_current_A);
L{end+1} = sprintf('TOTAL BATTERY CURRENT:       %6.3f A', r.total_battery_current_A);
L{end+1} = '';

% --- Safety margins ---
L{end+1} = '=== SAFETY MARGINS ===';
L{end+1} = sprintf('TB6612FNG continuous margin: %5.2f x   [%s]', ...
                   r.tb6612_margin, okflag(r.tb6612_margin, p.thr_tb6612_continuous));
L{end+1} = sprintf('TB6612FNG stall margin:      %5.2f x   [%s]', ...
                   r.tb6612_stall_margin, okflag(r.tb6612_stall_margin, p.thr_tb6612_stall));
L{end+1} = sprintf('Buck converter peak margin:  %5.2f x   [%s]', ...
                   r.buck_peak_margin, okflag(r.buck_peak_margin, p.thr_buck_peak));
L{end+1} = sprintf('Boost converter margin:      %5.2f x   [%s]', ...
                   r.boost_margin, okflag(r.boost_margin, p.thr_boost_margin));
L{end+1} = sprintf('Battery C-rating margin:     %5.2f x   [%s]', ...
                   r.battery_current_margin, okflag(r.battery_current_margin, p.thr_battery_C));
L{end+1} = '';

% --- Power balance check ---
useful_pct = 100 * r.total_useful_power_W / r.total_battery_power_W;
loss_pct   = 100 * r.total_loss_W / r.total_battery_power_W;
balance_ok = abs(r.total_battery_power_W - (r.total_useful_power_W + r.total_loss_W)) < 0.01;
L{end+1} = '=== POWER BALANCE CHECK ===';
L{end+1} = sprintf('Total battery power:  %6.3f W', r.total_battery_power_W);
L{end+1} = sprintf('Useful power:         %6.3f W  (%4.1f%%)', r.total_useful_power_W, useful_pct);
L{end+1} = sprintf('Conversion losses:    %6.3f W  (%4.1f%%)', r.total_loss_W, loss_pct);
L{end+1} = sprintf('[%s -- must balance within 0.01 W]', ternary(balance_ok, 'PASS', 'FAIL'));
L{end+1} = '';

% --- Battery runtime ---
L{end+1} = '=== BATTERY RUNTIME ===';
L{end+1} = sprintf('Nominal runtime (continuous draw): %5.1f minutes', r.runtime_minutes);
L{end+1} = sprintf('Usable runtime (80%% capacity):     %5.1f minutes', r.usable_runtime_minutes);
L{end+1} = sprintf('Worst-case (pessimistic eta sweep): %5.1f minutes  (boost %.2f / buck %.2f, %.3f A)', ...
                   worst_runtime_min, worst_boost_eff, worst_buck_eff, worst_current_A);
L{end+1} = '';

% --- Sensitivity table ---
L{end+1} = '=== EFFICIENCY SENSITIVITY SWEEP (3x3) ===';
L{end+1} = '| Boost eta | Buck eta | Total Battery Current (A) | Usable Runtime (min) |';
L{end+1} = '|-----------|----------|---------------------------|----------------------|';
for ib = 1:nB
    for ik = 1:nK
        marker = '';
        if ib == iwB && ik == iwK, marker = '  <-- worst case'; end
        L{end+1} = sprintf('|   %4.2f    |   %4.2f   |          %6.3f           |        %5.1f         |%s', ...
            p.boost_eff_sweep(ib), p.buck_eff_sweep(ik), ...
            sweep_current(ib, ik), sweep_runtime(ib, ik), marker); %#ok<AGROW>
    end
end
L{end+1} = '';

% --- Competition-day check ---
L{end+1} = '=== COMPETITION DAY CHECK ===';
L{end+1} = sprintf('Total runs planned:        %2d  (%d practice + %d competition)', ...
                   cd_total_runs, p.n_runs_practice, p.n_runs_competition);
L{end+1} = sprintf('Estimated charge used:     %6.3f Ah  (%4.1f%% of usable capacity)', ...
                   cd_charge_used_Ah, 100 * cd_charge_used_Ah / cd_usable_capacity_Ah);
L{end+1} = sprintf('Charge margin:             %5.2f x   [Single charge sufficient: %s]', ...
                   cd_charge_margin, ternary(cd_charge_margin >= 1.0, 'YES', 'NO'));
L{end+1} = '';

% --- Per-lap depletion & lap-time prediction (Section 6.2) ---
L{end+1} = '=== PER-LAP DEPLETION & LAP-TIME PREDICTION (from full charge) ===';
L{end+1} = sprintf('Operating point source:    %s', op.source);
L{end+1} = sprintf('Predicted lap time:        %5.2f s/lap  (run: %.2f s over %d laps)', ...
                   op.lap_time_s, op.run_time_s, op.n_laps);
if ~isnan(op.wheel_rpm)
    L{end+1} = sprintf('Predicted wheel speed:     %5.0f rpm', op.wheel_rpm);
end
L{end+1} = sprintf('Charge depleted per lap:   %6.2f mAh  (%.3f%% of full pack)', ...
                   lap.per_lap_charge_mAh, lap.soc_drop_per_lap_full_pct);
L{end+1} = sprintf('Energy depleted per lap:   %6.2f mWh  (%.2f J)', ...
                   lap.per_lap_energy_mWh, lap.per_lap_energy_J);
L{end+1} = sprintf('Laps on a full charge:     %5.1f laps to 80%% usable floor (%5.1f laps to empty)', ...
                   lap.laps_until_usable_floor, lap.laps_until_empty);
L{end+1} = sprintf('Distance on a full charge: %5.1f m to usable floor (%.1f m to empty)', ...
                   lap.dist_until_usable_floor_m, lap.dist_until_empty_m);
L{end+1} = sprintf('Full RUNS on a full charge:%5.1f runs (%d laps each)', ...
                   lap.runs_until_usable_floor, op.n_laps);
L{end+1} = '  Lap-by-lap SoC (from 100%, usable floor at 80% depth):';
L{end+1} = '  | Lap | Charge used (mAh) | Energy used (mWh) | SoC remaining (%) |';
L{end+1} = '  |-----|-------------------|-------------------|-------------------|';
for k = 1:numel(lap.table_lap)
    floor_mark = '';
    if lap.table_soc_pct(k) <= 100*(1 - p.usable_capacity_fraction)
        floor_mark = '  <-- below usable floor';
    end
    L{end+1} = sprintf('  | %3d |      %7.2f      |      %7.2f      |       %5.1f       |%s', ...
        lap.table_lap(k), lap.table_charge_mAh(k), lap.table_energy_mWh(k), ...
        lap.table_soc_pct(k), floor_mark); %#ok<AGROW>
end
L{end+1} = sprintf('  (Lap time held constant per the flat-7.4V assumption; real LiPo sag');
L{end+1} = sprintf('   would slow later laps -- see the SoC->voltage->lap-time model below.)');
L{end+1} = '';

% --- Voltage sag vs SoC and its lap-time effect (Section 6.3) ---
L{end+1} = '=== VOLTAGE SAG (SoC) -> LAP-TIME EFFECT ===';
if sag.lap_model_used
    L{end+1} = 'Lap time source:           lap-time advanced model re-run at each terminal voltage';
else
    L{end+1} = 'Lap time source:           FALLBACK sqrt(Vref/V) scaling [upload lap-time .m + optimal_design.mat for the real model]';
end
L{end+1} = sprintf('Internal resistance:       %.3f ohm  [ESTIMATE]', p.battery_internal_resistance_ohm);
L{end+1} = sprintf('Terminal V @ full charge:  %.2f V  -> %.3f s/lap', ...
                   sag.vterm_full_V, sag.laptime_full_per_lap_s);
L{end+1} = sprintf('Terminal V @ usable floor: %.2f V  -> %.3f s/lap  (SoC %.0f%%)', ...
                   sag.vterm_floor_V, sag.laptime_floor_per_lap_s, sag.usable_floor_soc_pct);
L{end+1} = sprintf('Lap-time penalty full->floor: +%.1f%% (%.3f s/lap slower)', ...
                   sag.slowdown_pct_full_to_floor, ...
                   sag.laptime_floor_per_lap_s - sag.laptime_full_per_lap_s);
L{end+1} = sprintf('Reference (flat %.1f V nominal): %.3f s/lap', ...
                   p.battery_voltage_nom_V, sag.laptime_nominal_per_lap_s);
L{end+1} = '  | SoC (%) | OCV (V) | Terminal V | Load I (A) | Lap time (s/lap) |';
L{end+1} = '  |---------|---------|------------|------------|------------------|';
soc_show = [100 80 60 40 20 0];
for sv = soc_show
    [~, ii] = min(abs(sag.soc_pct - sv));
    L{end+1} = sprintf('  |   %3d   |  %5.2f  |    %5.2f   |    %5.3f   |      %6.3f      |', ...
        sag.soc_pct(ii), sag.ocv_pack_V(ii), sag.vterm_V(ii), ...
        sag.iload_A(ii), sag.laptime_per_lap_s(ii)); %#ok<AGROW>
end
L{end+1} = '=========================================================';

% Print to console
for k = 1:numel(L), emit(L{k}); end

%% --- Section 4 / 3.6 warnings (raised as real MATLAB warnings) ----------
if r.tb6612_stall_margin < p.thr_tb6612_stall
    warning(['N20 stall current (%.2f A) exceeds TB6612FNG peak rating (%.2f A): ' ...
             'stall margin %.2f < 1.0. A physical jam could damage the driver.'], ...
            p.n20_stall_current_A, p.tb6612_peak_A_per_channel, r.tb6612_stall_margin);
end
if r.battery_current_margin < p.thr_battery_C
    warning(['Battery C-rating margin %.2f < 2.0: pack discharges at a high fraction of ' ...
             'its C-rating; significant sag/heating likely, invalidating the flat-7.4V model.'], ...
            r.battery_current_margin);
end
if cd_charge_margin < 1.0
    warning(['Competition-day charge margin %.2f < 1.0: a single charge is NOT sufficient ' ...
             'for the planned schedule. Plan a spare battery or a mid-day charge.'], ...
            cd_charge_margin);
end
if ~sag.lap_model_used
    warning(['Section 6.3 used the FALLBACK lap-time scaling. For the real ' ...
             'voltage->lap-time curve, place compute_lap_time_advanced.m (and ' ...
             'its helpers) plus optimal_design.mat on the path and re-run.']);
end

%% =====================================================================
%% SECTION 7.5 -- LOG FILE (timestamped)
%% =====================================================================
ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
log_name = sprintf('power_budget_log_%s.txt', ts);
fid = fopen(log_name, 'w');
if fid > 0
    for k = 1:numel(L), fprintf(fid, '%s\n', L{k}); end
    fclose(fid);
    fprintf('\nLog written: %s\n', log_name);
else
    warning('Could not open log file %s for writing.', log_name);
end

%% =====================================================================
%% SECTION 9 -- VALIDATION CHECKS (run before declaring done)
%% =====================================================================
fprintf('\n=== VALIDATION CHECK ===\n');
validate_range('Total battery current (A)', r.total_battery_current_A, 0.5, 1.0, 0.3, 2.0);
assert(r.boost_input_current_A > r.fan_current_12V_A, ...
    'Boost input current must exceed its output current -- efficiency applied backwards.');
fprintf('  Boost input %.3f A > output %.3f A  [OK efficiency direction]\n', ...
        r.boost_input_current_A, r.fan_current_12V_A);
assert(balance_ok, 'Power balance assertion failed at report time.');
fprintf('  Power balance PASS (%.4f W vs %.4f W)\n', ...
        r.total_battery_power_W, r.total_useful_power_W + r.total_loss_W);
validate_range('Nominal runtime (min)', r.runtime_minutes, 20, 30, 10, 120);
fprintf('  All validation checks passed.\n');

%% =====================================================================
%% SECTION 7.2-7.4 -- FIGURES
%% =====================================================================
make_figures(p, r, sweep_current, sweep_runtime, worst_runtime_min, cd_required_runtime_min);
make_lap_depletion_figure(p, lap, op);
make_voltage_laptime_figure(p, sag, op);

%% =====================================================================
%% SECTION 7.5 -- SAVE RESULTS FOR REUSE
%% =====================================================================
power_budget = struct();
power_budget.params              = p;
power_budget.result_nominal      = r;
power_budget.sweep_boost_eff     = p.boost_eff_sweep;
power_budget.sweep_buck_eff      = p.buck_eff_sweep;
power_budget.sweep_current_A     = sweep_current;
power_budget.sweep_runtime_min   = sweep_runtime;
power_budget.worst_case          = struct('boost_eff', worst_boost_eff, ...
                                          'buck_eff', worst_buck_eff, ...
                                          'current_A', worst_current_A, ...
                                          'runtime_min', worst_runtime_min);
power_budget.operating_point     = op;
power_budget.per_lap             = lap;
power_budget.voltage_sag         = sag;
power_budget.competition_day     = struct('total_runs', cd_total_runs, ...
                                          'charge_used_Ah', cd_charge_used_Ah, ...
                                          'usable_capacity_Ah', cd_usable_capacity_Ah, ...
                                          'charge_margin', cd_charge_margin, ...
                                          'required_runtime_min', cd_required_runtime_min);
power_budget.generated           = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
save('power_budget.mat', 'power_budget');
fprintf('Saved power_budget.mat (results for Simscape/Test-phase reuse).\n');

%% =====================================================================
%% LOCAL FUNCTIONS
%% =====================================================================

function loads = build_topology(p)
% Build the explicit load topology as a struct array. Each load carries its
% discrete current states (levels_A), the time-fraction at each state (duty,
% must sum to 1), a worst-case instantaneous peak (peak_A) for regulator
% survival checks, the rail it sits on, and a provenance string.
    L = struct('name', {}, 'rail', {}, 'levels_A', {}, 'duty', {}, ...
               'peak_A', {}, 'source', {});

    % 7.4V direct -- N20 motor via TB6612FNG (0 A when coasting/braked)
    L(end+1) = mkload('N20 motor', '7V4', ...
        [0, p.n20_typical_run_current_A], [1 - p.n20_duty_cycle, p.n20_duty_cycle], ...
        p.n20_stall_current_A, 'ESTIMATE run / CONFIRM stall');

    % 12V rail -- blower fan (current derived from rated power downstream)
    L(end+1) = mkload('Delta blower fan', '12V', ...
        p.fan_rated_power_W / p.fan_rated_voltage_V, 1.0, ...
        p.fan_max_current_A, 'DATASHEET');

    % 5V rail -- Raspberry Pi Zero 2W (three-state)
    L(end+1) = mkload('RPi Zero 2W', '5V', ...
        [p.rpi_idle_current_A, p.rpi_typical_current_A, p.rpi_peak_current_A], ...
        [p.rpi_duty.idle, p.rpi_duty.typical, p.rpi_duty.peak], ...
        p.rpi_peak_current_A, 'ESTIMATE');

    % 5V rail -- steering servo (idle/active, worst case = stall)
    L(end+1) = mkload('Steering servo', '5V', ...
        [p.servo_idle_current_A, p.servo_typical_current_A], ...
        [1 - p.servo_active_duty_cycle, p.servo_active_duty_cycle], ...
        p.servo_stall_current_A, 'ESTIMATE / CONFIRM stall');

    % 5V rail -- Arduino Nano ESP32 VIN (already includes its 3.3V rail)
    L(end+1) = mkload('Arduino Nano ESP32 (VIN)', '5V', ...
        [p.esp32_typical_current_A, p.esp32_peak_current_A], ...
        [1 - p.esp32_peak_duty_cycle, p.esp32_peak_duty_cycle], ...
        p.esp32_peak_current_A, 'ESTIMATE (incl. 3.3V rail)');

    % 3.3V rail -- ToF + IMU (downstream of ESP32; informational only,
    % NOT summed into the 5V bus -- see Section 3.5)
    L(end+1) = mkload('VL53L1X ToF x N', '3V3', ...
        p.tof_count * p.tof_current_per_unit_A * p.tof_duty_cycle, 1.0, ...
        p.tof_count * p.tof_current_per_unit_A, 'DATASHEET / CONFIRM count');
    L(end+1) = mkload('MPU6050 IMU', '3V3', ...
        p.imu_current_A * p.imu_duty_cycle, 1.0, p.imu_current_A, 'DATASHEET');

    loads = L;
end

function s = mkload(name, rail, levels_A, duty, peak_A, source)
% Helper to construct one load entry; structurally checks duty sums to 1.
    assert(abs(sum(duty) - 1.0) < 1e-6, ...
        sprintf('Duty fractions for load "%s" must sum to 1 (got %.4f).', name, sum(duty)));
    s = struct('name', name, 'rail', rail, 'levels_A', levels_A, ...
               'duty', duty, 'peak_A', peak_A, 'source', source);
end

function i_avg = avg_load_current(load)
% Duty-weighted average current of one load. The sum(duty)==1 guard is the
% structural protection against the "duty fractions don't sum to 1" class of
% bug, applied uniformly to every load (2-state, 3-state, or constant).
    assert(abs(sum(load.duty) - 1.0) < 1e-6, ...
        sprintf('Duty fractions for load "%s" must sum to 1.', load.name));
    i_avg = sum(load.levels_A .* load.duty);
end

function [i_in, p_in] = converter_input(p_out_W, efficiency, v_in_V)
% Input current/power of a switching converter. Power is NOT conserved:
% input power = output power / efficiency (the term students often drop).
    p_in = p_out_W / efficiency;
    i_in = p_in / v_in_V;
end

function r = compute_power_budget(p, boost_eff, buck_eff)
% Compute the full per-rail current/power budget for given converter
% efficiencies. Drives everything from the p.loads topology. The Section 4
% power-balance assertion runs here so it executes on EVERY evaluation,
% including each cell of the Section 5 sensitivity sweep.
    r = struct();

    % --- 3.1 12V rail (fan): use datasheet power directly ---
    fan = get_load(p.loads, 'Delta blower fan');
    r.fan_power_W       = p.fan_rated_power_W;
    r.fan_current_12V_A = r.fan_power_W / p.fan_rated_voltage_V;
    % Cross-check derived current against the datasheet rated current (>10% -> flag)
    if abs(r.fan_current_12V_A - p.fan_rated_current_A) / p.fan_rated_current_A > 0.10
        warning('Fan derived current %.3f A disagrees >10%% with datasheet %.3f A -- unit/data error?', ...
                r.fan_current_12V_A, p.fan_rated_current_A);
    end

    % --- 3.2 Boost converter input current (from 7.4V battery rail) ---
    r.boost_output_power_W = r.fan_power_W;
    [r.boost_input_current_A, r.boost_input_power_W] = ...
        converter_input(r.boost_output_power_W, boost_eff, p.battery_voltage_nom_V);

    % --- 3.3 5V rail aggregate (duty-weighted average per load, summed) ---
    rpi   = get_load(p.loads, 'RPi Zero 2W');
    servo = get_load(p.loads, 'Steering servo');
    esp32 = get_load(p.loads, 'Arduino Nano ESP32 (VIN)');
    r.rpi_avg_current_A   = avg_load_current(rpi);
    r.servo_avg_current_A = avg_load_current(servo);
    r.esp32_avg_current_A = avg_load_current(esp32);
    r.total_5V_avg_current_A = r.rpi_avg_current_A + r.servo_avg_current_A + r.esp32_avg_current_A;

    % Worst-case simultaneous-peak current on the 5V rail (regulator survival).
    % Reported SEPARATELY from the average draw used for runtime -- different
    % questions: "survive a bad instant" vs "how long does the battery last".
    r.worst_case_5V_current_A = rpi.peak_A + servo.peak_A + esp32.peak_A;
    r.buck_peak_margin        = p.buck_converter_rated_A / r.worst_case_5V_current_A;

    % --- 3.4 5V rail input current at the battery (apply buck efficiency) ---
    r.buck_output_power_W = r.total_5V_avg_current_A * p.buck_converter_output_V;
    [r.buck_input_current_A, r.buck_input_power_W] = ...
        converter_input(r.buck_output_power_W, buck_eff, p.battery_voltage_nom_V);

    % --- 3.5 3.3V rail (ToF + IMU), downstream of ESP32 internal regulator ---
    % IMPORTANT MODELLING DECISION (do NOT "fix" this as a missing term):
    % the 3.3V rail is powered by the ESP32 internal 5V->3.3V regulator, which
    % is itself fed from the 5V bus. esp32_typical/peak_current_A are defined
    % AT THE 5V VIN PIN and ALREADY INCLUDE this cascaded conversion and the
    % ToF+IMU loads. We therefore compute total_3V3_current_A for REPORTING
    % ONLY and deliberately do NOT add it to the 5V rail -- doing so would
    % double-count the sensors.
    tof = get_load(p.loads, 'VL53L1X ToF x N');
    imu = get_load(p.loads, 'MPU6050 IMU');
    r.tof_total_current_A = avg_load_current(tof);
    r.imu_current_avg_A   = avg_load_current(imu);
    r.total_3V3_current_A = r.tof_total_current_A + r.imu_current_avg_A;

    % --- 3.6 Direct 7.4V loop (N20 motor); ~0 A when coasting/braked ---
    motor = get_load(p.loads, 'N20 motor');
    r.n20_avg_current_A = avg_load_current(motor);

    % --- 4. Total battery current and power ---
    r.total_battery_current_A = r.n20_avg_current_A + r.boost_input_current_A + r.buck_input_current_A;
    r.total_battery_power_W   = r.total_battery_current_A * p.battery_voltage_nom_V;

    % Power-balance cross-check: total = useful + losses (within tolerance).
    r.total_useful_power_W = (r.n20_avg_current_A * p.battery_voltage_nom_V) + ...
                             r.fan_power_W + ...
                             (r.total_5V_avg_current_A * p.buck_converter_output_V);
    r.total_loss_W = (r.boost_input_power_W - r.boost_output_power_W) + ...
                     (r.buck_input_power_W - r.buck_output_power_W);
    assert(abs(r.total_battery_power_W - (r.total_useful_power_W + r.total_loss_W)) < 0.01, ...
        'Power balance check failed -- useful + losses must equal total battery power draw');

    % --- 6. Runtime (constant-current discharge; optimistic vs real sag) ---
    r.runtime_hours          = p.battery_capacity_Ah / r.total_battery_current_A;
    r.runtime_minutes        = r.runtime_hours * 60;
    r.usable_runtime_minutes = r.runtime_minutes * p.usable_capacity_fraction;
end

function op = load_operating_point(p)
% Import the drivetrain operating point (predicted lap time, lap count, wheel
% RPM) from the lap-time optimisation model's optimal_design.mat. This script
% CONSUMES this prediction; it does not recompute it. Falls back to flagged
% placeholders if the .mat is not on the path.
    op = struct();
    op.is_loaded        = false;
    op.source           = sprintf('FALLBACK placeholder (%s not found) [CONFIRM]', p.opt_design_file);
    op.run_time_s       = p.run_time_s_fallback;
    op.n_laps           = p.n_laps_fallback;
    op.lap_distance_m   = p.lap_distance_m;
    op.wheel_rpm        = NaN;
    % Fields needed to recompute lap time vs supply voltage (Section 6.3):
    op.has_lap_design   = false;
    op.lap_params       = struct();
    op.wheel_OD_mm      = NaN;
    op.bevel_ratio      = NaN;
    op.downforce_penalty= NaN;

    if exist(p.opt_design_file, 'file') == 2
        try
            S  = load(p.opt_design_file);
            od = S.optimal_design;
            op.run_time_s = od.lap_time_s;                 % total predicted run time (all laps)
            if isfield(od, 'params') && isfield(od.params, 'n_laps')
                op.n_laps = od.params.n_laps;
            end
            if isfield(od, 'params') && isfield(od.params, 'lap_distance_m')
                op.lap_distance_m = od.params.lap_distance_m;
            end
            if isfield(od, 'wheel_rpm'), op.wheel_rpm = od.wheel_rpm; end
            % Design point for re-running the advanced lap-time model at any voltage
            if isfield(od, 'params'), op.lap_params = od.params; end
            if isfield(od, 'wheel_OD_mm'), op.wheel_OD_mm = od.wheel_OD_mm; end
            if isfield(od, 'bevel_ratio_real')                 % prefer manufacturable gear
                op.bevel_ratio = od.bevel_ratio_real;
            elseif isfield(od, 'bevel_ratio')
                op.bevel_ratio = od.bevel_ratio;
            end
            if isfield(od, 'downforce_penalty'), op.downforce_penalty = od.downforce_penalty; end
            op.has_lap_design = isstruct(op.lap_params) && ~isempty(fieldnames(op.lap_params)) ...
                                && ~isnan(op.wheel_OD_mm) && ~isnan(op.bevel_ratio);
            mdl = 'advanced';
            if isfield(od, 'model'), mdl = od.model; end
            op.source     = sprintf('optimal_design.mat (lap-time %s model)', mdl);
            op.is_loaded  = true;
        catch err
            warning('Could not read %s (%s) -- using fallback operating point.', ...
                    p.opt_design_file, err.message);
        end
    end
    op.lap_time_s = op.run_time_s / op.n_laps;   % predicted per-lap time
end

function lap = compute_lap_depletion(p, r, op)
% From a FULLY CHARGED pack, predict per-lap charge/energy depletion and the
% lap-by-lap state-of-charge schedule. Depletion is correlated with the
% predicted lap time: longer laps cost proportionally more charge/energy.
    lap = struct();
    Vbat = p.battery_voltage_nom_V;

    % Per-lap cost (constant-current model at the nominal total battery draw)
    lap.per_lap_charge_Ah  = r.total_battery_current_A * op.lap_time_s / 3600;
    lap.per_lap_charge_mAh = lap.per_lap_charge_Ah * 1000;
    lap.per_lap_energy_Wh  = r.total_battery_power_W * op.lap_time_s / 3600;
    lap.per_lap_energy_mWh = lap.per_lap_energy_Wh * 1000;
    lap.per_lap_energy_J   = r.total_battery_power_W * op.lap_time_s;

    % SoC drop per lap, as % of full nameplate and of the usable budget
    lap.soc_drop_per_lap_full_pct   = 100 * lap.per_lap_charge_Ah / p.battery_capacity_Ah;
    usable_Ah = p.battery_capacity_Ah * p.usable_capacity_fraction;
    lap.soc_drop_per_lap_usable_pct = 100 * lap.per_lap_charge_Ah / usable_Ah;

    % Laps / distance / runs achievable on one full charge
    lap.laps_until_usable_floor = usable_Ah / lap.per_lap_charge_Ah;
    lap.laps_until_empty        = p.battery_capacity_Ah / lap.per_lap_charge_Ah;
    lap.dist_until_usable_floor_m = lap.laps_until_usable_floor * op.lap_distance_m;
    lap.dist_until_empty_m        = lap.laps_until_empty * op.lap_distance_m;
    lap.runs_until_usable_floor   = lap.laps_until_usable_floor / op.n_laps;

    % Dense lap-by-lap schedule from 100% SoC down to the usable floor (for the
    % depletion figure). Capped to keep the plot light if the pack lasts a lot
    % of laps.
    n_floor = max(1, ceil(lap.laps_until_usable_floor)) + 1;
    if n_floor <= 400
        lap.fig_lap = (0:n_floor)';
    else
        lap.fig_lap = round(linspace(0, n_floor, 400))';
    end
    lap.fig_soc = soc_at(lap.fig_lap, lap.per_lap_charge_mAh, p.battery_capacity_Ah);

    % Sampled checkpoints for the console/log table (~12 rows, always including
    % the lap that crosses the usable floor), so the report stays readable even
    % when the pack sustains many laps.
    floor_lap = ceil(lap.laps_until_usable_floor);
    if floor_lap <= 14
        chk = (1:floor_lap)';
    else
        chk = unique(round(linspace(1, floor_lap, 12)))';
    end
    chk = unique([chk; floor_lap]);
    lap.table_lap        = chk;
    lap.table_charge_mAh = chk * lap.per_lap_charge_mAh;
    lap.table_energy_mWh = chk * lap.per_lap_energy_mWh;
    lap.table_soc_pct    = soc_at(chk, lap.per_lap_charge_mAh, p.battery_capacity_Ah);
    lap.predicted_lap_time_s = op.lap_time_s;   % held constant (flat-voltage model)
end

function soc = soc_at(lap_idx, per_lap_charge_mAh, capacity_Ah)
% State of charge (%) remaining after lap_idx laps from a full charge.
    soc = 100 * (1 - (lap_idx * per_lap_charge_mAh / 1000) / capacity_Ah);
    soc(soc < 0) = 0;
end

function sag = compute_soc_voltage_laptime(p, r, op)
% Section 6.3 -- sag-aware extension. Model how pack terminal voltage falls with
% state of charge (SoC) and under load, then feed that voltage into the lap-time
% optimisation model (assumed uploaded) to predict how the lap time lengthens as
% the battery drains.
%
% Terminal voltage under load: the regulated rails behave roughly as a constant
% power sink P (input current rises as voltage falls), so with pack OCV(SoC) and
% internal resistance R the steady operating point solves
%     V = OCV - I*R,  I = P/V   ->   V^2 - OCV*V + P*R = 0
% taking the physical (larger) root. P is held at the nominal total battery
% power (flagged approximation -- the motor term actually grows mildly with V).
    sag = struct();
    soc = (100:-5:p.soc_plot_min_pct)';

    ocv_cell = interp1(p.lipo_soc_breakpoints_pct, p.lipo_ocv_per_cell_V, soc, 'pchip');
    ocv_pack = p.battery_series_cells * ocv_cell;

    P = r.total_battery_power_W;
    R = p.battery_internal_resistance_ohm;
    disc = ocv_pack.^2 - 4*P*R;
    disc(disc < 0) = 0;
    vterm = (ocv_pack + sqrt(disc)) / 2;

    sag.soc_pct    = soc;
    sag.ocv_pack_V = ocv_pack;
    sag.vterm_V    = vterm;
    sag.iload_A    = P ./ vterm;

    % Lap time at each terminal voltage (and at the flat-7.4V nominal reference)
    [sag.laptime_run_s, sag.laptime_per_lap_s, sag.lap_model_used] = ...
        laptime_at_voltage(vterm, p, op);
    [sag.laptime_nominal_run_s, sag.laptime_nominal_per_lap_s] = ...
        laptime_at_voltage(p.battery_voltage_nom_V, p, op);

    % Headline: full charge vs the usable (80% depth) floor
    floor_soc = 100 * (1 - p.usable_capacity_fraction);
    sag.usable_floor_soc_pct  = floor_soc;
    sag.vterm_full_V          = vterm(1);
    sag.vterm_floor_V         = interp1(soc, vterm, floor_soc);
    sag.laptime_full_per_lap_s  = sag.laptime_per_lap_s(1);
    sag.laptime_floor_per_lap_s = interp1(soc, sag.laptime_per_lap_s, floor_soc);
    sag.slowdown_pct_full_to_floor = ...
        100 * (sag.laptime_floor_per_lap_s / sag.laptime_full_per_lap_s - 1);
end

function [t_run, t_lap, used] = laptime_at_voltage(V, p, op)
% Predicted run/lap time as a function of supply voltage. Prefers the uploaded
% advanced lap-time model (re-run with params.supply_voltage_V = V); falls back
% to a flagged analytical scaling if the lap-time files / design are unavailable.
    V = V(:);
    t_run = zeros(size(V));
    have_model = (exist('compute_lap_time_advanced', 'file') == 2);

    if have_model && op.has_lap_design
        used = true;
        pl = op.lap_params;
        for k = 1:numel(V)
            pl.supply_voltage_V = V(k);
            o = compute_lap_time_advanced(op.wheel_OD_mm, op.bevel_ratio, ...
                                          op.downforce_penalty, pl);
            t_run(k) = o.t_total_s;
        end
    else
        used = false;
        % Fallback: straights scale ~1/V (top speed proportional to motor
        % no-load speed proportional to V), corners are grip-limited and
        % V-independent. Without the straight/corner split we approximate the
        % run time about the nominal point as proportional to sqrt(Vref/V).
        Vref  = p.battery_voltage_nom_V;
        t_run = op.run_time_s * sqrt(Vref ./ V);
    end
    t_lap = t_run / op.n_laps;
end

function load = get_load(loads, name)
% Look up a load entry by name from the topology struct array.
    idx = find(strcmp({loads.name}, name), 1);
    assert(~isempty(idx), 'Load "%s" not found in topology.', name);
    load = loads(idx);
end

function av = assumptions_to_verify(p)
% Auto-generate the "assumptions requiring verification" list. Each entry is a
% parameter flagged [ESTIMATE] or [CONFIRM] in Section 2 that the team must
% bench-measure or look up before trusting the model's safety margins.
    av = struct('tag', {}, 'name', {}, 'value', {}, 'note', {});
    add = @(tag, name, val, note) struct('tag', tag, 'name', name, 'value', val, 'note', note);

    av(end+1) = add('CONFIRM',  'battery_capacity_mAh',  sprintf('%g', p.battery_capacity_mAh),       'verify against actual pack');
    av(end+1) = add('CONFIRM',  'battery_C_rating',      sprintf('%g', p.battery_max_continuous_discharge_C), 'read off pack label');
    av(end+1) = add('CONFIRM',  'n20_stall_current_A',   sprintf('%g', p.n20_stall_current_A),        'from actual N20 variant datasheet');
    av(end+1) = add('ESTIMATE', 'n20_run_current_A',     sprintf('%g', p.n20_typical_run_current_A),  'current-clamp on the bench');
    av(end+1) = add('ESTIMATE', 'n20_duty_cycle',        sprintf('%g', p.n20_duty_cycle),             'log from a real run');
    av(end+1) = add('ESTIMATE', 'boost_efficiency',      sprintf('%g', p.boost_converter_efficiency), 'bench measure in/out power');
    av(end+1) = add('CONFIRM',  'boost_max_output_A',    sprintf('%g', p.boost_converter_max_output_A),'KOOBOOK module spec');
    av(end+1) = add('ESTIMATE', 'buck_efficiency',       sprintf('%g', p.buck_converter_efficiency),  'bench measure in/out power');
    av(end+1) = add('CONFIRM',  'buck_rated_A',          sprintf('%g', p.buck_converter_rated_A),      'confirm module rating');
    av(end+1) = add('ESTIMATE', 'rpi_currents_A',        sprintf('%.2f/%.2f/%.2f', p.rpi_idle_current_A, p.rpi_typical_current_A, p.rpi_peak_current_A), 'USB power meter under real load');
    av(end+1) = add('CONFIRM',  'servo_stall_current_A', sprintf('%g', p.servo_stall_current_A),       'servo datasheet');
    av(end+1) = add('ESTIMATE', 'esp32_currents_A',      sprintf('%.2f/%.2f', p.esp32_typical_current_A, p.esp32_peak_current_A), 'measure at VIN (incl. 3.3V rail)');
    av(end+1) = add('ESTIMATE', 'esp32_3v3_efficiency',  sprintf('%g', p.esp32_internal_3v3_efficiency), 'assumed; folded into VIN figures');
    av(end+1) = add('CONFIRM',  'tof_count',             sprintf('%g', p.tof_count),                   'count actual ToF sensors');
    av(end+1) = add('CONFIRM',  'schedule_runs',         sprintf('%d+%d', p.n_runs_practice, p.n_runs_competition), 'actual day schedule');
    av(end+1) = add('CONFIRM',  'idle_between_runs_s',   sprintf('%g', p.idle_between_runs_s),          'time between runs at venue');
    av(end+1) = add('ESTIMATE', 'idle_elec_fraction',    sprintf('%g', p.idle_electronics_fraction),   'does firmware sleep between runs?');
end

function s = okflag(margin, threshold)
% Returns 'OK' or 'WARNING' depending on whether margin meets the threshold.
    if margin >= threshold
        s = 'OK';
    else
        s = 'WARNING';
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function validate_range(name, val, lo_ok, hi_ok, lo_hard, hi_hard)
% Print a plausibility check. Hard bounds raise an error (likely unit bug);
% soft bounds only print an advisory.
    if val < lo_hard || val > hi_hard
        error('VALIDATION FAILED: %s = %.4f outside hard plausibility band [%.3f, %.3f] -- likely a unit error.', ...
              name, val, lo_hard, hi_hard);
    end
    if val < lo_ok || val > hi_ok
        fprintf('  %-32s = %8.3f  [ADVISORY: outside expected %.2f-%.2f]\n', name, val, lo_ok, hi_ok);
    else
        fprintf('  %-32s = %8.3f  [OK, within %.2f-%.2f]\n', name, val, lo_ok, hi_ok);
    end
end

function v = struct2array_compat(s)
% Portable struct2array (Octave lacks it): return all field values as a row.
    c = struct2cell(s);
    v = [c{:}];
end

function make_figures(p, r, sweep_current, sweep_runtime, worst_runtime_min, required_runtime_min)
% Build the three required figures and export them at 300 DPI.

    % ---- Figure 1: power distribution (horizontal stacked bar) ----
    f1 = figure('Name', 'Power Distribution', 'Color', 'w');
    motor_W     = r.n20_avg_current_A * p.battery_voltage_nom_V;
    fan_rail_W  = r.fan_power_W;
    fan_loss_W  = r.boost_input_power_W - r.boost_output_power_W;
    rail5_W     = r.total_5V_avg_current_A * p.buck_converter_output_V;
    rail5_loss_W= r.buck_input_power_W - r.buck_output_power_W;
    seg = [motor_W, fan_rail_W, fan_loss_W, rail5_W, rail5_loss_W];
    seg_names = {'Motor power', 'Fan rail power', 'Fan rail loss', ...
                 '5V rail power', '5V rail loss'};
    % barh needs >=2 rows for 'stacked'; pad a dummy row and hide it.
    hb = barh([seg; nan(size(seg))], 'stacked');
    cols = [0.20 0.45 0.70; 0.30 0.65 0.40; 0.75 0.80 0.45; ...
            0.85 0.45 0.20; 0.90 0.75 0.35];
    for k = 1:numel(hb), set(hb(k), 'FaceColor', cols(k, :)); end
    ylim([0.5 1.5]); set(gca, 'YTick', 1, 'YTickLabel', {'Battery input'});
    xlabel('Power (W)');
    title(sprintf('Battery power distribution (total %.2f W)', r.total_battery_power_W));
    legend(seg_names, 'Location', 'eastoutside');
    grid on;
    export_fig_compat(f1, 'fig1_power_distribution.png');

    % ---- Figure 2: sensitivity heatmap (total battery current) ----
    f2 = figure('Name', 'Efficiency Sensitivity', 'Color', 'w');
    boost_lbl = arrayfun(@(x) sprintf('%.2f', x), p.boost_eff_sweep, 'UniformOutput', false);
    buck_lbl  = arrayfun(@(x) sprintf('%.2f', x), p.buck_eff_sweep,  'UniformOutput', false);
    used_heatmap = false;
    if exist('heatmap', 'file') == 2 || exist('heatmap', 'builtin') == 5
        try
            % rows = buck eta (y), cols = boost eta (x); transpose to match
            hm = heatmap(boost_lbl, buck_lbl, sweep_current'); %#ok<NASGU>
            hm.Title  = 'Total battery current (A)';
            hm.XLabel = 'Boost \eta';
            hm.YLabel = 'Buck \eta';
            used_heatmap = true;
        catch
            used_heatmap = false;
        end
    end
    if ~used_heatmap
        imagesc(sweep_current');
        set(gca, 'XTick', 1:numel(boost_lbl), 'XTickLabel', boost_lbl, ...
                 'YTick', 1:numel(buck_lbl),  'YTickLabel', buck_lbl, ...
                 'YDir', 'normal');
        colorbar;
        try, colormap(parula); catch, colormap(jet); end  % parula not in Octave
        xlabel('Boost \eta'); ylabel('Buck \eta');
        title('Total battery current (A)');
        for ib = 1:numel(boost_lbl)
            for ik = 1:numel(buck_lbl)
                text(ib, ik, sprintf('%.3f', sweep_current(ib, ik)), ...
                     'HorizontalAlignment', 'center', 'Color', 'k', 'FontWeight', 'bold');
            end
        end
    end
    export_fig_compat(f2, 'fig2_sensitivity_heatmap.png');

    % ---- Figure 3: runtime comparison bar chart ----
    f3 = figure('Name', 'Runtime Comparison', 'Color', 'w');
    vals  = [r.runtime_minutes, r.usable_runtime_minutes, worst_runtime_min, required_runtime_min];
    names = {'Nominal', 'Usable (80%)', 'Worst-case \eta', 'Day requirement'};
    hb3 = bar(vals);
    set(hb3, 'FaceColor', 'flat');
    try
        hb3.CData = [0.20 0.45 0.70; 0.30 0.65 0.40; 0.85 0.45 0.20; 0.55 0.30 0.60];
    catch
    end
    set(gca, 'XTickLabel', names);
    ylabel('Minutes'); grid on;
    title('Battery runtime vs competition-day active-driving requirement');
    for k = 1:numel(vals)
        text(k, vals(k), sprintf('%.1f', vals(k)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
    export_fig_compat(f3, 'fig3_runtime_comparison.png');
end

function export_fig_compat(fh, fname)
% Export at 300 DPI via exportgraphics where available; else fall back to print.
    try
        if exist('exportgraphics', 'file') == 2 || exist('exportgraphics', 'builtin') == 5
            exportgraphics(fh, fname, 'Resolution', 300);
        else
            print(fh, fname, '-dpng', '-r300');
        end
        fprintf('Wrote figure: %s\n', fname);
    catch err
        warning('Could not export %s: %s', fname, err.message);
    end
end

function make_lap_depletion_figure(p, lap, op)
% Figure 4: battery state-of-charge depletion vs lap number from a full charge,
% annotated with the per-lap energy cost and the 80% usable floor. Makes the
% link between predicted lap time and how many laps the pack sustains visible.
    f4 = figure('Name', 'Per-Lap Depletion', 'Color', 'w');

    laps = lap.fig_lap;          % dense schedule, lap 0 = 100% SoC
    soc  = lap.fig_soc;
    plot(laps, soc, '-', 'LineWidth', 1.8, 'Color', [0.20 0.45 0.70]);
    hold on; grid on;

    floor_pct = 100 * (1 - p.usable_capacity_fraction);   % e.g. 80% depth -> 20% remaining
    xl = [0, max(laps)];
    plot(xl, [floor_pct floor_pct], 'r--', 'LineWidth', 1.5);
    text(xl(1), floor_pct, sprintf(' usable floor (%.0f%% remaining)', floor_pct), ...
         'Color', 'r', 'VerticalAlignment', 'bottom');

    % Mark the lap at which the usable floor is crossed
    nfloor = lap.laps_until_usable_floor;
    if nfloor <= max(laps)
        plot([nfloor nfloor], [0 floor_pct], 'r:', 'LineWidth', 1.2);
        text(nfloor, floor_pct + 5, sprintf('%.0f laps ', nfloor), ...
             'Color', 'r', 'HorizontalAlignment', 'right');
    end

    xlabel('Lap number (from full charge)');
    ylabel('Battery state of charge (%)');
    ylim([0 100]); xlim([0 max(laps)]);
    title({sprintf('Per-lap depletion: %.2f mAh/lap @ %.2f s/lap (predicted)', ...
                   lap.per_lap_charge_mAh, op.lap_time_s), ...
           sprintf('%.0f laps / %.1f runs to usable floor on a full charge', ...
                   nfloor, lap.runs_until_usable_floor)});
    legend({'State of charge', 'Usable floor'}, 'Location', 'northeast');
    export_fig_compat(f4, 'fig4_per_lap_depletion.png');
end

function make_voltage_laptime_figure(p, sag, op)
% Figure 5: how pack voltage and predicted lap time vary with state of charge.
% Top panel = terminal & open-circuit voltage vs SoC; bottom panel = predicted
% lap time vs SoC, against the flat-7.4V nominal reference. SoC axis is reversed
% so discharge runs left (full) -> right (empty).
    f5 = figure('Name', 'Voltage & Lap Time vs SoC', 'Color', 'w');
    floor_soc = sag.usable_floor_soc_pct;
    yl = @() ylim();

    % --- Top: voltage vs SoC ---
    subplot(2, 1, 1);
    plot(sag.soc_pct, sag.ocv_pack_V, '--', 'LineWidth', 1.4, 'Color', [0.5 0.5 0.5]);
    hold on; grid on;
    plot(sag.soc_pct, sag.vterm_V, '-', 'LineWidth', 2.0, 'Color', [0.20 0.45 0.70]);
    plot([p.battery_voltage_nom_V*0+min(sag.soc_pct) max(sag.soc_pct)], ...
         [p.battery_voltage_nom_V p.battery_voltage_nom_V], ':', ...
         'Color', [0.85 0.45 0.20], 'LineWidth', 1.2);
    v = axis; plot([floor_soc floor_soc], v(3:4), 'r--', 'LineWidth', 1.2);
    text(floor_soc, v(3) + 0.85*(v(4)-v(3)), sprintf(' usable floor (%.0f%%)', floor_soc), 'Color', 'r');
    set(gca, 'XDir', 'reverse');
    xlabel('State of charge (%)'); ylabel('Pack voltage (V)');
    title(sprintf('Battery voltage vs SoC (R_{int} = %.2f \\Omega, load %.2f W)', ...
                  p.battery_internal_resistance_ohm, sag.iload_A(1)*sag.vterm_V(1)));
    legend({'Open-circuit (OCV)', 'Terminal (under load)', ...
            sprintf('Flat %.1f V model', p.battery_voltage_nom_V)}, ...
           'Location', 'southwest');

    % --- Bottom: lap time vs SoC ---
    subplot(2, 1, 2);
    plot(sag.soc_pct, sag.laptime_per_lap_s, '-o', 'LineWidth', 1.8, ...
         'Color', [0.55 0.30 0.60], 'MarkerFaceColor', [0.55 0.30 0.60], 'MarkerSize', 3);
    hold on; grid on;
    plot([min(sag.soc_pct) max(sag.soc_pct)], ...
         [sag.laptime_nominal_per_lap_s sag.laptime_nominal_per_lap_s], ':', ...
         'Color', [0.85 0.45 0.20], 'LineWidth', 1.2);
    v = axis; plot([floor_soc floor_soc], v(3:4), 'r--', 'LineWidth', 1.2);
    set(gca, 'XDir', 'reverse');
    xlabel('State of charge (%)'); ylabel('Predicted lap time (s/lap)');
    if sag.lap_model_used
        src = 'advanced lap-time model';
    else
        src = 'fallback scaling (upload lap-time model)';
    end
    title(sprintf('Lap time vs SoC: +%.1f%% full->floor  [%s]', ...
                  sag.slowdown_pct_full_to_floor, src));
    legend({'Predicted lap time', sprintf('Flat %.1f V reference', p.battery_voltage_nom_V)}, ...
           'Location', 'northeast');

    export_fig_compat(f5, 'fig5_voltage_laptime_vs_soc.png');
end
