function out = compute_lap_time(wheel_OD_mm, bevel_ratio, downforce_penalty, params)
%COMPUTE_LAP_TIME  Physics model for the WRO 2026 drivetrain lap-time estimate.
%
%   out = COMPUTE_LAP_TIME(wheel_OD_mm, bevel_ratio, downforce_penalty, params)
%
%   Computes predicted 3-lap time (and all physically meaningful intermediate
%   values) for an autonomous WRO Future Engineers car, given:
%       wheel_OD_mm       - rear wheel outer diameter [mm] (scalar or array)
%       bevel_ratio       - bevel gear step-up ratio (driver/driven teeth)
%                           (scalar or array, broadcast-compatible with wheel_OD_mm)
%       downforce_penalty - fractional speed loss from the downforce system
%                           (scalar, e.g. 0.15 == 15% reduction)
%       params            - struct of fixed project constants (see
%                           wro2026_laptime_optimisation.m, Section 1)
%
%   The function is fully vectorised: pass meshgrid matrices for wheel_OD_mm and
%   bevel_ratio to evaluate the whole design grid in one call. It returns a
%   struct OUT whose fields are the same size as the (broadcast) inputs, so the
%   grid sweep, the constraint masks (Section 4) and the journal figures
%   (Section 6) can all read intermediate quantities, not just the final time.
%
%   DBTL context: this is the "Design" phase artifact for Cycle 1 (drivetrain
%   proof of concept). Its output (optimal wheel OD + bevel ratio) becomes a
%   fixed input parameter in the Cycle 1 Simscape plant model used for "Test".
%
%   See also: WRO2026_LAPTIME_OPTIMISATION

% ------------------------------------------------------------------------
% 3.1 Motor output (Rev. 3: voltage-scaled from rated datasheet point)
% ------------------------------------------------------------------------
% No-load speed scales ~linearly with applied voltage for a DC motor
% (omega_noload proportional to V). This ignores the small effect of voltage
% on winding losses, which is an acceptable simplification at this modelling
% level (stated as an assumption in the Engineer's Journal).
voltage_ratio            = params.supply_voltage_V / params.n20_rated_voltage_V;   % ~1.233
n20_output_rpm_noload    = params.n20_rated_rpm * voltage_ratio;                   % ~1850 RPM @ 7.4V
n20_output_rpm_operating = n20_output_rpm_noload * params.n20_load_factor;         % ~1202 RPM under load
n20_op_torque_Nm         = params.n20_stall_torque_Nm * params.n20_op_torque_frac; % operating torque

% ------------------------------------------------------------------------
% 3.2 Wheel RPM after step-up bevel gear
% ------------------------------------------------------------------------
wheel_rpm             = n20_output_rpm_operating .* bevel_ratio;
wheel_circumference_m = pi .* wheel_OD_mm ./ 1000;
wheel_speed_mps       = wheel_rpm .* wheel_circumference_m ./ 60;

% ------------------------------------------------------------------------
% 3.3 Torque delivered to each wheel (torque divides as speed multiplies)
% ------------------------------------------------------------------------
torque_at_diff_input_Nm = (n20_op_torque_Nm ./ bevel_ratio) .* params.eta_bevel;
torque_per_wheel_Nm     = (torque_at_diff_input_Nm .* params.eta_diff) ./ 2;  % split over 2 rear wheels

% ------------------------------------------------------------------------
% 3.4 Force and torque required to meet target acceleration
% ------------------------------------------------------------------------
F_drive_N    = params.car_mass_kg * params.target_accel_mps2;
F_rolling_N  = params.Crr * params.car_mass_kg * params.g;
F_total_N    = F_drive_N + F_rolling_N;
wheel_radius_m = (wheel_OD_mm ./ 1000) ./ 2;
torque_required_per_wheel_Nm = (F_total_N .* wheel_radius_m) ./ 2;

% ------------------------------------------------------------------------
% 3.5 Torque margin (constraint check, not a penalty)
% ------------------------------------------------------------------------
torque_margin = torque_per_wheel_Nm ./ torque_required_per_wheel_Nm;

% ------------------------------------------------------------------------
% 3.6 Corner skid-limited speed (depends only on physics, not gearing)
% ------------------------------------------------------------------------
v_max_corner_mps = sqrt(params.mu_tire_vinyl * params.g * params.corner_radius_m);
% With the downforce fan adding normal force (the BENEFIT side of the system):
v_max_corner_with_fan_mps = sqrt( params.mu_tire_vinyl ...
    * (params.car_mass_kg * params.g + params.F_fan_N) / params.car_mass_kg ...
    * params.corner_radius_m );

% ------------------------------------------------------------------------
% 3.7 Effective speeds used in lap time (Rev. 3: downforce penalty applied)
% ------------------------------------------------------------------------
% The downforce speed penalty (the COST side of the system) is a multiplicative
% derating on the raw gear-limited wheel speed, applied BEFORE the corner skid
% clamp so it lowers the ceiling the clamp is compared against (avoids
% double-counting). It is kept entirely distinct from the fan grip benefit in
% v_max_corner_with_fan_mps above.
downforce_factor        = 1 - downforce_penalty;          % e.g. 0.85 at 15%
wheel_speed_derated_mps = wheel_speed_mps .* downforce_factor;

% Straight: apply a top-speed safety factor (do not run flat-out at the limit).
v_straight_mps = min(wheel_speed_derated_mps, ...
                     params.straight_safety_factor .* wheel_speed_derated_mps);

% Corner: take the lower of gear-deliverable speed and friction-allowed speed.
v_corner_mps   = min(wheel_speed_derated_mps, v_max_corner_with_fan_mps);

% ------------------------------------------------------------------------
% 3.8 Lap time calculation
% ------------------------------------------------------------------------
total_straight_dist_m = params.straight_dist_per_lap_m * params.corners_per_lap * params.n_laps;
total_corner_dist_m   = (params.lap_distance_m * params.n_laps) - total_straight_dist_m;

t_straight_s = total_straight_dist_m ./ v_straight_mps;
t_corner_s   = total_corner_dist_m   ./ v_corner_mps;
t_total_s    = t_straight_s + t_corner_s;

% A point is "corner-grip-limited" when friction (not the drivetrain) sets the
% cornering speed -- a key regime flag for the journal narrative.
corner_grip_limited = wheel_speed_derated_mps >= v_max_corner_with_fan_mps;

% ------------------------------------------------------------------------
% Pack everything the sweep / constraints / figures need.
% ------------------------------------------------------------------------
out = struct();
% --- scalar derived motor quantities (same for every grid point) ---
out.voltage_ratio            = voltage_ratio;
out.n20_output_rpm_noload    = n20_output_rpm_noload;
out.n20_output_rpm_operating = n20_output_rpm_operating;
out.n20_op_torque_Nm         = n20_op_torque_Nm;
out.v_max_corner_mps         = v_max_corner_mps;
out.v_max_corner_with_fan_mps = v_max_corner_with_fan_mps;
% --- per-design-point fields (match size of broadcast inputs) ---
out.wheel_OD_mm              = wheel_OD_mm + zeros(size(wheel_speed_mps));
out.bevel_ratio             = bevel_ratio + zeros(size(wheel_speed_mps));
out.downforce_penalty        = downforce_penalty;
out.downforce_factor         = downforce_factor;
out.wheel_rpm                = wheel_rpm + zeros(size(wheel_speed_mps));
out.wheel_circumference_m    = wheel_circumference_m + zeros(size(wheel_speed_mps));
out.wheel_speed_mps          = wheel_speed_mps;
out.wheel_speed_derated_mps  = wheel_speed_derated_mps;
out.torque_per_wheel_Nm      = torque_per_wheel_Nm + zeros(size(wheel_speed_mps));
out.torque_required_per_wheel_Nm = torque_required_per_wheel_Nm + zeros(size(wheel_speed_mps));
out.torque_margin            = torque_margin + zeros(size(wheel_speed_mps));
out.v_straight_mps           = v_straight_mps;
out.v_corner_mps             = v_corner_mps + zeros(size(wheel_speed_mps));
out.t_straight_s             = t_straight_s;
out.t_corner_s               = t_corner_s + zeros(size(wheel_speed_mps));
out.t_total_s                = t_total_s;
out.corner_grip_limited      = corner_grip_limited + false(size(wheel_speed_mps));
end
