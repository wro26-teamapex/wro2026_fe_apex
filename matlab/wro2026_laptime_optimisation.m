%% WRO 2026 Future Engineers -- Lap-Time Optimisation Model (MATLAB)
% =========================================================================
% DBTL CONTEXT
% -------------------------------------------------------------------------
% This script is the "DESIGN" phase artifact for Cycle 1 (drivetrain proof of
% concept) of the Design-Build-Test-Learn engineering cycle. It searches for
% the optimal REAR-WHEEL DIAMETER and BEVEL-GEAR STEP-UP RATIO that minimise
% predicted 3-lap time subject to physical constraints (car footprint, motor
% torque, skid limit, and the active-downforce speed penalty).
%
% Its output -- the optimal (wheel OD, bevel ratio) point -- becomes a FIXED
% input parameter in the Cycle 1 Simscape plant model used for the "TEST"
% phase. For that reason every parameter name/unit below is chosen for direct
% reuse, and the optimum is exported to optimal_design.mat for load() in the
% Simscape step (rather than duplicating constants across files).
%
% Revision 3 changes implemented here:
%   1. Motor RPM scaled from the datasheet rated point (1500 RPM @ 6V) by
%      supply-voltage ratio only (NO internal-gear-ratio division).
%   2. Active-downforce speed penalty added as an explicit multiplicative
%      derating, swept across the 10-20% sensitivity band.
%   3. Car footprint corrected to 70 mm x 115 mm (propagated for consistency).
%
% Files:  wro2026_laptime_optimisation.m  (this script)
%         compute_lap_time.m              (vectorised physics model)
% =========================================================================

clear; clc; close all;

%% 1. Fixed Project Parameters (constants -- NOT optimised)
% Every constant is traceable for the Engineer's Journal: see inline source.
p = struct();

% --- Track geometry ---
p.lap_distance_m           = 7.15;   % m, one lap, mid-lane path estimate
p.n_laps                   = 3;      % competition run length
p.target_time_s            = 15;     % s, HARD ceiling, must not exceed
p.design_time_s            = 12;     % s, soft target with ~20% buffer
p.corner_radius_m          = 0.50;   % m, mid-lane corner radius estimate
p.corners_per_lap          = 4;      % count
p.straight_dist_per_lap_m  = 1.00;   % m, length of one straight segment

% --- Car physical constraints (Rev. 3: corrected footprint) ---
p.car_width_mm        = 70;          % mm, axle span / overall width
p.car_length_mm       = 115;         % mm, CORRECTED from 100 mm (Rev. 3)
p.car_mass_kg         = 0.18;        % kg, estimated total mass (mass budget)
p.max_tire_width_mm   = 14;          % mm, available width per wheel in 70 mm span
p.downforce_area_frac = 2/3;         % fraction of footprint covered by duct
p.downforce_duct_area_mm2 = p.car_width_mm * p.car_length_mm * p.downforce_area_frac;
% (informational only: used to sanity-check F_fan_N against duct size below;
%  NOT consumed by the lap-time equations.)

% --- Motor: N20, rated point taken DIRECTLY from datasheet (Rev. 3) ---
% IMPORTANT: 1500 RPM @ 6V is the manufacturer-rated OUTPUT-SHAFT speed; it
% already accounts for the N20's internal gearbox. Do NOT divide by any
% separate internal gear ratio (that was the previous revision's error).
% Speed scaling is by simple voltage ratio (DC no-load speed ~ linear in V).
p.n20_rated_rpm       = 1500;   % RPM, rated no-load output speed at rated V (datasheet)
p.n20_rated_voltage_V = 6.0;    % V, rated voltage (datasheet)
p.supply_voltage_V    = 7.4;    % V, actual pack voltage (2S LiPo)
p.n20_load_factor     = 0.65;   % operating RPM as fraction of no-load (load property)
p.n20_stall_torque_Nm = 0.08;   % Nm, stall torque at output shaft AT RATED 6V.
                                % Treated as voltage-independent here (conservative:
                                % slightly under-estimates torque at 7.4 V).
p.n20_op_torque_frac  = 0.40;   % operating torque as fraction of stall torque

% --- Active downforce speed penalty (Rev. 3: NEW) ---
% 10-20% reduction in total achievable car speed from the downforce fan/duct
% (fan current draw, duct drag, added mass). Swept, not fixed.
p.downforce_speed_penalty_range = [0.10, 0.15, 0.20];  % low / mid / high
p.downforce_penalty_primary     = 0.15;                % mid value -> headline surface

% --- Friction / environment ---
p.mu_tire_vinyl = 0.75;   % TPU 95A tire on vinyl competition mat
p.Crr           = 0.02;   % rolling resistance coefficient
p.g             = 9.81;   % m/s^2

% --- Gear mesh efficiencies ---
p.eta_bevel = 0.92;   % PETG bevel gear mesh efficiency
p.eta_diff  = 0.95;   % differential internal gear efficiency

% --- Downforce fan (grip BENEFIT side -- separate from the speed penalty) ---
p.F_fan_N = 0.10;     % N, estimated thrust at chosen PWM duty cycle

% --- Drivetrain / dynamics design assumptions ---
p.target_accel_mps2      = 1.6;    % m/s^2, 0 -> nominal speed in ~1 s (Section 3.4)
p.straight_safety_factor = 0.95;   % run straights at 95% of derated top speed (Section 3.7)

% --- Constraint thresholds (Section 4) ---
p.min_torque_margin   = 1.2;   % require >=20% torque headroom
p.max_wheel_speed_mps = 2.2;   % realistic top speed cap

% Sanity-check print: fan thrust per unit duct area vs typical ducted-fan figures.
fan_thrust_per_mm2 = p.F_fan_N / p.downforce_duct_area_mm2;     % N/mm^2
fprintf('--- Parameter sanity checks ---\n');
fprintf('Car footprint            : %d mm x %d mm\n', p.car_width_mm, p.car_length_mm);
fprintf('Downforce duct area      : %.0f mm^2 (%.0f%% of footprint)\n', ...
        p.downforce_duct_area_mm2, 100*p.downforce_area_frac);
fprintf('Fan thrust               : %.3f N  -> %.2e N/mm^2 over duct\n', ...
        p.F_fan_N, fan_thrust_per_mm2);
fprintf('  (plausibility check only -- not a constraint)\n\n');

%% 2. Design Variables to Sweep
% Variable 1: wheel outer diameter [mm], 22..32 in 0.5 mm steps.
% Variable 2: bevel step-up ratio,      1.0..2.5 in 0.05 steps.
% Variable 3 (sensitivity, NOT optimised): downforce penalty [0.10 0.15 0.20].
wheel_OD_vec    = 22:0.5:32;     % mm
bevel_ratio_vec = 1.0:0.05:2.5;  % -

[wheel_OD_grid, bevel_ratio_grid] = meshgrid(wheel_OD_vec, bevel_ratio_vec);

%% 3-5. Run the full 2D grid search ONCE PER downforce penalty value
penalties   = p.downforce_speed_penalty_range;
nPen        = numel(penalties);
results(nPen) = struct('penalty',[],'surface',[],'feasible',[], ...
    'opt_OD',[],'opt_ratio',[],'opt_time',[],'opt_margin',[], ...
    'opt_v_straight',[],'opt_v_corner',[],'opt_wheel_rpm',[], ...
    'opt_corner_limited',[],'detail',[]);

for k = 1:nPen
    pen = penalties(k);

    % --- evaluate the whole grid in one vectorised call (Section 3) ---
    d = compute_lap_time(wheel_OD_grid, bevel_ratio_grid, pen, p);

    % --- 4. Constraints as logical masks; infeasible -> NaN (honest surface)
    feasible = true(size(wheel_OD_grid));
    feasible = feasible & (d.torque_margin   >= p.min_torque_margin);   % >=20% headroom
    feasible = feasible & (d.wheel_speed_mps <= p.max_wheel_speed_mps); % realistic top speed
    feasible = feasible & (d.t_total_s       <= p.target_time_s);       % beat 15 s ceiling

    lap_time_surface = d.t_total_s;
    lap_time_surface(~feasible) = NaN;

    % diagnostic masks (stored for plots)
    mask_motor_stall  = d.torque_margin < 1.0;          % genuinely infeasible
    mask_corner_limit = d.corner_grip_limited;          % informational (already clamped)

    % --- 5A. Brute-force grid search optimum (global min ignoring NaNs) ---
    [opt_time, lin_idx] = min(lap_time_surface(:));
    [iy, ix] = ind2sub(size(lap_time_surface), lin_idx);
    opt_OD    = wheel_OD_grid(iy, ix);
    opt_ratio = bevel_ratio_grid(iy, ix);

    % stash everything for this penalty
    results(k).penalty            = pen;
    results(k).surface            = lap_time_surface;
    results(k).feasible           = feasible;
    results(k).mask_motor_stall   = mask_motor_stall;
    results(k).mask_corner_limit  = mask_corner_limit;
    results(k).opt_OD             = opt_OD;
    results(k).opt_ratio          = opt_ratio;
    results(k).opt_time           = opt_time;
    results(k).opt_margin         = d.torque_margin(iy, ix);
    results(k).opt_v_straight     = d.v_straight_mps(iy, ix);
    results(k).opt_v_corner       = d.v_corner_mps(iy, ix);
    results(k).opt_wheel_rpm      = d.wheel_rpm(iy, ix);
    results(k).opt_corner_limited = d.corner_grip_limited(iy, ix);
    results(k).detail             = d;
end

% index of the primary (mid) penalty case for the headline figures
kPrimary = find(abs(penalties - p.downforce_penalty_primary) < 1e-9, 1);
if isempty(kPrimary), kPrimary = 2; end
R   = results(kPrimary);
det = R.detail;

%% 5B. fmincon refinement (secondary -- constrained optimisation credibility)
% Same physics objective, started from the grid optimum to avoid local minima.
fmincon_OD = NaN; fmincon_ratio = NaN; fmincon_time = NaN; fmincon_ok = false;
if exist('fmincon', 'file')
    objfun  = @(x) getfield(compute_lap_time(x(1), x(2), p.downforce_penalty_primary, p), 't_total_s');
    nonlcon = @(x) deal( ...
        p.min_torque_margin - ...
            getfield(compute_lap_time(x(1), x(2), p.downforce_penalty_primary, p), 'torque_margin'), ...
        []);  % c <= 0 : 1.2 - torque_margin <= 0 ; no equality constraint
    lb = [22, 1.0];
    ub = [32, 2.5];
    x0 = [R.opt_OD, R.opt_ratio];
    opts = optimoptions('fmincon', 'Display', 'off', 'Algorithm', 'sqp');
    try
        [xopt, fopt] = fmincon(objfun, x0, [], [], [], [], lb, ub, nonlcon, opts);
        fmincon_OD = xopt(1); fmincon_ratio = xopt(2); fmincon_time = fopt;
        fmincon_ok = true;
    catch ME
        warning('fmincon failed (%s); reporting grid-search result only.', ME.message);
    end
else
    fprintf(['[info] fmincon not available in this MATLAB/Octave install -- ' ...
             'reporting grid-search optimum only.\n\n']);
end

%% 6.1 Console / journal summary block
fprintf('=== OPTIMAL DESIGN POINT (downforce penalty = %.0f%%, PRIMARY/mid) ===\n', ...
        100*p.downforce_penalty_primary);
fprintf('Wheel OD:           %.1f mm\n',          R.opt_OD);
fprintf('Bevel ratio:        %.2f : 1\n',         R.opt_ratio);
fprintf('Wheel RPM:          %.0f RPM\n',         R.opt_wheel_rpm);
fprintf('Predicted speed:    %.2f m/s (straight), %.2f m/s (corner)\n', ...
        R.opt_v_straight, R.opt_v_corner);
fprintf('Torque margin:      %.2f x\n',           R.opt_margin);
fprintf('Predicted lap time: %.1f s   (target: <%g s, margin: %.1f s)\n', ...
        R.opt_time, p.target_time_s, p.target_time_s - R.opt_time);
if R.opt_corner_limited
    fprintf('NOTE: design is corner-grip-limited, not motor-limited, at this operating point.\n');
else
    fprintf('NOTE: design is motor/gear-speed-limited at this operating point.\n');
end
fprintf('\n--- Derived motor quantities (Rev. 3 voltage scaling) ---\n');
fprintf('Voltage ratio (7.4/6.0):   %.3f\n',   det.voltage_ratio);
fprintf('No-load RPM @ 7.4V:        %.0f RPM\n', det.n20_output_rpm_noload);
fprintf('Operating RPM (x%.2f load): %.0f RPM\n', p.n20_load_factor, det.n20_output_rpm_operating);
fprintf('Operating torque:          %.4f Nm\n', det.n20_op_torque_Nm);
fprintf('Corner skid limit (w/fan): %.2f m/s\n', det.v_max_corner_with_fan_mps);

fprintf('\n--- Optimiser cross-check (Method A grid vs Method B fmincon) ---\n');
fprintf('Grid search   : OD = %.2f mm, ratio = %.3f, t = %.3f s\n', ...
        R.opt_OD, R.opt_ratio, R.opt_time);
if fmincon_ok
    fprintf('fmincon       : OD = %.2f mm, ratio = %.3f, t = %.3f s\n', ...
            fmincon_OD, fmincon_ratio, fmincon_time);
    if abs(fmincon_time - R.opt_time) > 0.05*R.opt_time
        warning(['Grid and fmincon optima differ by >5%% -- investigate as a bug, ' ...
                 'do not report as a result.']);
    else
        fprintf('  -> agree within grid resolution. OK.\n');
    end
end
fprintf('\n');

%% 6.6 Downforce penalty sensitivity: table + CSV + flag
fprintf('=== DOWNFORCE PENALTY SENSITIVITY ===\n');
fprintf('%-18s %-18s %-16s %-18s %-14s\n', ...
        'downforce_penalty','optimal_wheel_OD_mm','optimal_bevel_ratio', ...
        'optimal_lap_time_s','torque_margin');
sens = zeros(nPen, 5);
for k = 1:nPen
    fprintf('%-18.2f %-18.1f %-16.2f %-18.3f %-14.2f\n', ...
        results(k).penalty, results(k).opt_OD, results(k).opt_ratio, ...
        results(k).opt_time, results(k).opt_margin);
    sens(k,:) = [results(k).penalty, results(k).opt_OD, results(k).opt_ratio, ...
                 results(k).opt_time, results(k).opt_margin];
end

% flag if the pessimistic case breaches the hard ceiling
[~, kHigh] = max(penalties);
if results(kHigh).opt_time > p.target_time_s || isnan(results(kHigh).opt_time)
    warning('At %.0f%% downforce penalty, design exceeds %g s target (best feasible = %.2f s).', ...
            100*penalties(kHigh), p.target_time_s, results(kHigh).opt_time);
else
    fprintf('All penalty cases remain under the %g s ceiling (worst = %.2f s at %.0f%%).\n\n', ...
            p.target_time_s, results(kHigh).opt_time, 100*penalties(kHigh));
end

% write CSV
csv_name = 'downforce_penalty_sensitivity.csv';
fid = fopen(csv_name, 'w');
fprintf(fid, 'downforce_penalty,optimal_wheel_OD_mm,optimal_bevel_ratio,optimal_lap_time_s,torque_margin\n');
for k = 1:nPen
    fprintf(fid, '%.2f,%.1f,%.2f,%.3f,%.2f\n', sens(k,1), sens(k,2), sens(k,3), sens(k,4), sens(k,5));
end
fclose(fid);
fprintf('Sensitivity table written to %s\n\n', csv_name);

%% 6.2 Figure 1 -- 3D surface (headline)
f1 = figure('Name','Lap Time Optimisation Surface','Color','w','Position',[100 100 900 650]);
surf(wheel_OD_grid, bevel_ratio_grid, R.surface, 'EdgeColor','none'); hold on;
try, colormap(turbo); catch, colormap(parula); end
cb = colorbar;
try cb.Label.String = '3-lap time (s)'; catch, try ylabel(cb,'3-lap time (s)'); catch, end; end
% optimal point marker
plot3(R.opt_OD, R.opt_ratio, R.opt_time, 'rp', ...
      'MarkerSize', 18, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'k', 'LineWidth', 1.2);
% 15 s competition-legal reference plane
xl = [min(wheel_OD_vec) max(wheel_OD_vec)];
yl = [min(bevel_ratio_vec) max(bevel_ratio_vec)];
[px, py] = meshgrid(xl, yl);
surf(px, py, p.target_time_s*ones(size(px)), ...
     'FaceColor',[0.6 0.6 0.6],'FaceAlpha',0.25,'EdgeColor','none');
xlabel('Wheel OD (mm)'); ylabel('Bevel ratio (-)'); zlabel('3-lap time (s)');
title('Lap Time Optimisation Surface -- Wheel Diameter vs Bevel Gear Ratio');
legend({'lap-time surface','optimum','15 s ceiling'},'Location','northeast');
view(135,30); grid on; hold off;

%% 6.3 Figure 2 -- 2D filled contour
f2 = figure('Name','Lap Time Contour','Color','w','Position',[120 120 850 620]);
contourf(wheel_OD_grid, bevel_ratio_grid, R.surface, 15, 'LineColor','none'); hold on;
try, colormap(turbo); catch, colormap(parula); end
cb2 = colorbar;
try cb2.Label.String = '3-lap time (s)'; catch, try ylabel(cb2,'3-lap time (s)'); catch, end; end
leg_h = []; leg_txt = {};
% infeasible (torque margin < 1.2) shaded as a semi-transparent grey overlay
infeasible_margin = double(det.torque_margin < p.min_torque_margin);
if any(infeasible_margin(:)) && ~all(infeasible_margin(:))
    try
        [~, hc] = contourf(wheel_OD_grid, bevel_ratio_grid, infeasible_margin, [0.5 0.5]);
        set(hc, 'FaceColor', [0.5 0.5 0.5], 'FaceAlpha', 0.35, 'LineColor', 'none');
        leg_h(end+1) = hc; leg_txt{end+1} = 'infeasible: torque margin < 1.2';
    catch
    end
end
hopt = plot(R.opt_OD, R.opt_ratio, 'rp', 'MarkerSize',16,'MarkerFaceColor','r','MarkerEdgeColor','k');
leg_h(end+1) = hopt; leg_txt{end+1} = 'optimum';
xlabel('Wheel OD (mm)'); ylabel('Bevel ratio (-)');
title(sprintf('3-Lap Time Contour (downforce penalty %.0f%%)', 100*R.penalty));
legend(leg_h, leg_txt, 'Location','northeast');
grid on; hold off;

%% 6.4 Figure 3 -- single-parameter sensitivity slices through the optimum
f3 = figure('Name','Parameter Sensitivity Slices','Color','w','Position',[140 140 1000 420]);

% Left: lap time vs wheel OD at optimum bevel ratio
subplot(1,2,1);
dOD = compute_lap_time(wheel_OD_vec, R.opt_ratio, R.penalty, p);
tOD = dOD.t_total_s;
feasOD = (dOD.torque_margin >= p.min_torque_margin) & ...
         (dOD.wheel_speed_mps <= p.max_wheel_speed_mps) & ...
         (dOD.t_total_s <= p.target_time_s);
tOD(~feasOD) = NaN;
plot(wheel_OD_vec, tOD, 'b-', 'LineWidth', 1.8); hold on;
plot(R.opt_OD, R.opt_time, 'rp', 'MarkerSize',14,'MarkerFaceColor','r');
xlabel('Wheel OD (mm)'); ylabel('3-lap time (s)');
title(sprintf('Lap time vs Wheel OD  (bevel = %.2f)', R.opt_ratio));
grid on; hold off;

% Right: lap time vs bevel ratio at optimum wheel OD
subplot(1,2,2);
dBR = compute_lap_time(R.opt_OD, bevel_ratio_vec, R.penalty, p);
tBR = dBR.t_total_s;
feasBR = (dBR.torque_margin >= p.min_torque_margin) & ...
         (dBR.wheel_speed_mps <= p.max_wheel_speed_mps) & ...
         (dBR.t_total_s <= p.target_time_s);
tBR(~feasBR) = NaN;
plot(bevel_ratio_vec, tBR, 'b-', 'LineWidth', 1.8); hold on;
plot(R.opt_ratio, R.opt_time, 'rp', 'MarkerSize',14,'MarkerFaceColor','r');
xlabel('Bevel ratio (-)'); ylabel('3-lap time (s)');
title(sprintf('Lap time vs Bevel ratio  (OD = %.1f mm)', R.opt_OD));
grid on; hold off;

%% 6.6 Figure 4 -- downforce penalty vs optimal lap time
f4 = figure('Name','Downforce Penalty Sensitivity','Color','w','Position',[160 160 760 540]);
plot(100*penalties, sens(:,4), 'o-', 'LineWidth',2,'MarkerSize',9,'MarkerFaceColor','b'); hold on;
try
    yline(p.target_time_s, 'r--', '15 s ceiling', 'LineWidth',1.5);
catch
    xlim_now = [100*min(penalties) 100*max(penalties)];
    plot(xlim_now, [p.target_time_s p.target_time_s], 'r--', 'LineWidth',1.5);
    text(xlim_now(1), p.target_time_s, ' 15 s ceiling', 'Color','r','VerticalAlignment','bottom');
end
for k = 1:nPen
    text(100*penalties(k), sens(k,4), sprintf('  %.2f s', sens(k,4)), 'FontSize',9);
end
xlabel('Downforce speed penalty (%)'); ylabel('Optimal 3-lap time (s)');
title('Downforce Penalty Sensitivity -- Optimal Lap Time vs Penalty');
grid on; hold off;

%% 6.7 Export figures (300 DPI) and optimal values (.mat)
try
    exportgraphics(f1, 'fig1_laptime_surface.png',      'Resolution', 300);
    exportgraphics(f2, 'fig2_laptime_contour.png',      'Resolution', 300);
    exportgraphics(f3, 'fig3_sensitivity_slices.png',   'Resolution', 300);
    exportgraphics(f4, 'fig4_downforce_sensitivity.png','Resolution', 300);
    fprintf('Figures saved as PNG (300 DPI).\n');
catch ME
    warning('exportgraphics unavailable (%s); falling back to print().', ME.message);
    print(f1,'fig1_laptime_surface.png','-dpng','-r300');
    print(f2,'fig2_laptime_contour.png','-dpng','-r300');
    print(f3,'fig3_sensitivity_slices.png','-dpng','-r300');
    print(f4,'fig4_downforce_sensitivity.png','-dpng','-r300');
end

% Save optimal design (mid case) + full sensitivity for the Simscape step.
optimal_design = struct();
optimal_design.wheel_OD_mm        = R.opt_OD;
optimal_design.bevel_ratio        = R.opt_ratio;
optimal_design.downforce_penalty  = R.penalty;
optimal_design.lap_time_s         = R.opt_time;
optimal_design.wheel_rpm          = R.opt_wheel_rpm;
optimal_design.v_straight_mps     = R.opt_v_straight;
optimal_design.v_corner_mps       = R.opt_v_corner;
optimal_design.torque_margin      = R.opt_margin;
optimal_design.corner_grip_limited = R.opt_corner_limited;
optimal_design.params             = p;
optimal_design.sensitivity_table  = sens;   % [penalty OD ratio time margin]
save('optimal_design.mat', 'optimal_design');
fprintf('Optimal design saved to optimal_design.mat\n\n');

%% 8. Validation check against Section 8 reference values (mid case)
fprintf('=== VALIDATION CHECK: compute_lap_time(28, 1.5, 0.15, params) ===\n');
vref = compute_lap_time(28, 1.5, 0.15, p);
checks = {
    'motor no-load RPM @7.4V', vref.n20_output_rpm_noload,    1850;
    'motor operating RPM',     vref.n20_output_rpm_operating, 1200;
    'wheel RPM',               vref.wheel_rpm,                1800;
    'wheel speed (pre-penalty)', vref.wheel_speed_mps,        2.64;
    'wheel speed (post 15%)',  vref.wheel_speed_derated_mps,  2.25;
    'torque margin',           vref.torque_margin,            4.1;
    'corner skid limit (fan)', vref.v_max_corner_with_fan_mps,1.97;
    'predicted lap time',      vref.t_total_s,                10.4;
};
all_ok = true;
for i = 1:size(checks,1)
    name = checks{i,1}; got = checks{i,2}; ref = checks{i,3};
    err = 100*abs(got-ref)/ref;
    flag = '';
    if err > 5, flag = '  <-- DEVIATES >5%, DEBUG'; all_ok = false; end
    fprintf('  %-26s got %9.3f  ref %9.3f  (%.1f%%)%s\n', name, got, ref, err, flag);
end
if vref.corner_grip_limited
    fprintf('  regime: corner-grip-limited at reference point (as expected).\n');
end
if all_ok
    fprintf('VALIDATION PASSED: all reference values within 5%%.\n\n');
else
    error('VALIDATION FAILED: reference deviation >5%% -- debug Section 3 equations.');
end
