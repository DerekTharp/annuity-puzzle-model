# Forward Monte Carlo simulation of lifecycle paths.
# Given a solved model (HealthSolution), simulates individual trajectories
# by drawing medical shocks, health transitions, and survival outcomes.
# Used for validating model moments against HRS data.

using Random
using Interpolations

struct SimulationResult
    wealth_path::Vector{Float64}
    consumption_path::Vector{Float64}
    health_path::Vector{Int}
    medical_path::Vector{Float64}
    age_at_death::Int
    bequest::Float64
end

"""
Simulate a single lifecycle trajectory from age 65 to death.

Given initial state (W_0, A_nominal, H_0), draws medical shocks,
health transitions, and survival outcomes each period. Consumption
is read from the policy function via interpolation.

Returns a SimulationResult with the full trajectory.
"""
function simulate_lifecycle(
    sol::HealthSolution,
    W_0::Float64,
    A_nominal::Float64,
    H_0::Int,
    base_surv::Vector{Float64},
    ss_func::Function,
    p::ModelParams;
    rng::AbstractRNG=Random.default_rng(),
    c_interps::Union{Matrix, Nothing}=nothing,
)
    g = sol.grids
    T = p.T
    # Use OBJECTIVE survival for forward simulation: actual death is governed
    # by physical mortality, not the agent's belief. Subjective survival
    # (with p.survival_pessimism applied) is already baked into the value
    # function used to compute the policy, so the consumption choice is correct
    # under the agent's beliefs; the forward draws here just need to reflect
    # actual mortality.
    surv_health = build_health_survival(base_surv, p; psi_override=1.0)
    health_trans = build_all_health_transitions(p)

    wealth_path = zeros(T)
    consumption_path = zeros(T)
    health_path = zeros(Int, T)
    medical_path = zeros(T)

    W = W_0
    H = H_0
    age_at_death = p.age_end
    bequest = 0.0

    A_nom_c = clamp(A_nominal, g.A[1], g.A[end])

    # Build health-weighted continuation interpolations for each (ih, t)
    # so we can re-optimize consumption given the realized medical shock
    # (matching solve.jl's source-aware accounting). The stored c_policy is
    # E_m[c*(m)] -- the m-averaged optimum -- which is not what the agent
    # would do at any single realized m. Re-optimizing fixes that. The
    # continuation V at (t+1) is health-weighted using the current period's
    # health-transition matrix.
    if c_interps === nothing
        # Caller did not precompute V_hw_interps; build them locally for
        # this single simulation. simulate_batch precomputes them across
        # threads to amortize the cost.
        nW = length(g.W); nA = length(g.A); nH = 3
        V_hw_interps = Matrix{Any}(undef, nH, T)
        for ih in 1:nH
            for tt in 1:T
                if tt < T
                    V_hw = zeros(nW, nA)
                    for ih_next in 1:nH
                        prob = health_trans[tt][ih, ih_next]
                        @views V_hw .+= prob .* sol.V[:, :, ih_next, tt + 1]
                    end
                else
                    # Terminal period: continuation is bequest only;
                    # solve_consumption handles this via the surv=0 path.
                    V_hw = zeros(nW, nA)
                end
                V_hw_interps[ih, tt] = linear_interpolation(
                    (g.W, g.A), V_hw,
                    extrapolation_bc=Interpolations.Flat(),
                )
            end
        end
    end

    for t in 1:T
        age = p.age_start + t - 1
        wealth_path[t] = W
        health_path[t] = H

        # Inflation-adjusted annuity income (with deferral support)
        A_real = annuity_income_real(A_nominal, t, p)

        ss_val = ss_func(age, p)

        # Draw medical expense shock
        m = 0.0
        if p.medical_enabled
            mu_m, sigma_m = medical_expense_params(age, H, p)
            m = exp(mu_m + sigma_m * randn(rng))
        end
        medical_path[t] = m

        # Source-aware accounting (matches solve.jl): medical absorbs
        # income first, then portfolio. The Medicaid floor lifts inc_after
        # if total resources fall below c_floor.
        inc_gross = ss_val + A_real
        inc_after = max(0.0, inc_gross - m)
        port_drain = max(0.0, m - inc_gross)
        W_after = max(W - port_drain, 0.0)
        if inc_after + W_after < p.c_floor
            inc_after = p.c_floor - W_after
        end

        # Re-optimize consumption given the realized shock. solve_consumption
        # handles the SDU kink and the c_floor corner. The continuation is
        # the health-weighted V at t+1 evaluated at the agent's nominal A.
        W_after_c = clamp(W_after, g.W[1], g.W[end])
        V_hw_interp_2d = c_interps === nothing ? V_hw_interps[H, t] : c_interps[H, t]
        # Build a 1D continuation V(W) at the agent's fixed nominal A.
        V_next_interp = let A_fixed = A_nom_c, V_hw_2d = V_hw_interp_2d
            W_eval -> V_hw_2d(clamp(W_eval, g.W[1], g.W[end]), A_fixed)
        end
        s_t_h = surv_health[t, H]
        _, c = solve_consumption(W_after_c, 0.0, inc_after,
                                 V_next_interp, s_t_h, p, t, H)
        consumption_path[t] = c

        # Next-period wealth: cash net of consumption. The wealth used here
        # MUST be the same value passed to solve_consumption above (W_after_c).
        # Earlier code used W_after (unclamped) which created a hoarding
        # feedback loop for agents whose wealth drifted above g.W[end]:
        # solve_consumption picked c as if W = W_max, but W_next was then
        # built from cash = inc + W_actual >> W_max, so the agent
        # under-consumed and W grew further. Using the clamped value
        # consistently makes the cap behave as a soft truncation: agents
        # at or above the cap consume at the cap-state policy and W_next
        # stays near the cap, matching the value-function convention used
        # to solve the model.
        cash = inc_after + W_after_c
        W_next = (1.0 + p.r) * (cash - c)
        W_next = max(W_next, 0.0)

        # Survival draw
        s = surv_health[t, H]
        if rand(rng) > s || t == T
            bequest = W_next
            age_at_death = age
            break
        end

        # Health transition draw
        u = rand(rng)
        cum = 0.0
        H_next = 3
        for h_next in 1:3
            cum += health_trans[t][H, h_next]
            if u < cum
                H_next = h_next
                break
            end
        end

        W = W_next
        H = H_next
    end

    return SimulationResult(
        wealth_path, consumption_path, health_path, medical_path,
        age_at_death, bequest,
    )
end

"""
Simulate n_sim lifecycle trajectories from a fixed initial state
and return aggregate statistics.

Returns a NamedTuple with:
- mean_wealth_by_age: average wealth at each age (among survivors)
- mean_consumption_by_age: average consumption at each age
- alive_fraction: fraction surviving to each age
- bequests: vector of all bequests
- mean_bequest: unconditional mean bequest
- frac_positive_bequest: fraction with bequest > 0
"""
function simulate_batch(
    sol::HealthSolution,
    W_0::Float64,
    A_nominal::Float64,
    H_0::Int,
    base_surv::Vector{Float64},
    ss_func::Function,
    p::ModelParams;
    n_sim::Int=10_000,
    rng_seed::Int=42,
)
    rng = Random.MersenneTwister(rng_seed)
    T = p.T
    g = sol.grids

    # Precompute health-weighted V continuation interpolations once.
    # simulate_lifecycle re-optimizes consumption given the realized medical
    # shock (matching solve.jl's source-aware accounting). The continuation
    # V at (t+1) is health-weighted using the current period's health
    # transition matrix; we precompute these 2D (W, A) interps here so
    # individual sims share the work.
    nW = length(g.W); nA = length(g.A); nH = 3
    health_trans_pre = build_all_health_transitions(p)
    c_interps = Matrix{Any}(undef, nH, T)  # name preserved for backward compat
    for ih in 1:nH
        for t in 1:T
            if t < T
                V_hw = zeros(nW, nA)
                for ih_next in 1:nH
                    prob = health_trans_pre[t][ih, ih_next]
                    @views V_hw .+= prob .* sol.V[:, :, ih_next, t + 1]
                end
            else
                V_hw = zeros(nW, nA)  # terminal: continuation is zero (bequest handled elsewhere)
            end
            c_interps[ih, t] = linear_interpolation(
                (g.W, g.A), V_hw,
                extrapolation_bc=Interpolations.Flat(),
            )
        end
    end

    wealth_sums = zeros(T)
    wealth_sq_sums = zeros(T)
    consumption_sums = zeros(T)
    medical_sums = zeros(T)
    alive_count = zeros(Int, T)
    health_counts = zeros(Int, T, 3)
    bequests = Vector{Float64}(undef, n_sim)

    # Collect individual wealth paths for percentile computation
    all_wealth = fill(NaN, n_sim, T)

    for i in 1:n_sim
        result = simulate_lifecycle(
            sol, W_0, A_nominal, H_0, base_surv, ss_func, p;
            rng=rng, c_interps=c_interps,
        )
        death_t = result.age_at_death - p.age_start + 1
        for t in 1:min(death_t, T)
            w = result.wealth_path[t]
            wealth_sums[t] += w
            wealth_sq_sums[t] += w^2
            consumption_sums[t] += result.consumption_path[t]
            medical_sums[t] += result.medical_path[t]
            alive_count[t] += 1
            all_wealth[i, t] = w
            h = result.health_path[t]
            if h >= 1 && h <= 3
                health_counts[t, h] += 1
            end
        end
        bequests[i] = result.bequest
    end

    mean_wealth = [alive_count[t] > 0 ? wealth_sums[t] / alive_count[t] : 0.0
                   for t in 1:T]
    mean_consumption = [alive_count[t] > 0 ? consumption_sums[t] / alive_count[t] : 0.0
                        for t in 1:T]
    mean_medical = [alive_count[t] > 0 ? medical_sums[t] / alive_count[t] : 0.0
                    for t in 1:T]
    alive_frac = [alive_count[t] / n_sim for t in 1:T]

    # Wealth percentiles among survivors at each age
    wealth_p25 = zeros(T)
    wealth_p50 = zeros(T)
    wealth_p75 = zeros(T)
    for t in 1:T
        vals = filter(!isnan, all_wealth[:, t])
        if length(vals) >= 4
            sort!(vals)
            n = length(vals)
            wealth_p25[t] = vals[max(1, round(Int, 0.25 * n))]
            wealth_p50[t] = vals[max(1, round(Int, 0.50 * n))]
            wealth_p75[t] = vals[max(1, round(Int, 0.75 * n))]
        end
    end

    # Bequest statistics
    pos_beq = filter(b -> b > 0, bequests)
    frac_pos = length(pos_beq) / n_sim
    mean_beq = sum(bequests) / n_sim
    median_beq = sort(bequests)[max(1, div(n_sim, 2))]
    frac_beq_10k = count(b -> b > 10_000, bequests) / n_sim

    # Health state prevalence by age (fraction in each state among survivors)
    health_prevalence = zeros(T, 3)
    for t in 1:T
        if alive_count[t] > 0
            for h in 1:3
                health_prevalence[t, h] = health_counts[t, h] / alive_count[t]
            end
        end
    end

    return (
        mean_wealth_by_age=mean_wealth,
        mean_consumption_by_age=mean_consumption,
        mean_medical_by_age=mean_medical,
        alive_fraction=alive_frac,
        bequests=bequests,
        mean_bequest=mean_beq,
        median_bequest=median_beq,
        frac_positive_bequest=frac_pos,
        frac_bequest_above_10k=frac_beq_10k,
        health_counts=health_counts,
        health_prevalence=health_prevalence,
        alive_count=alive_count,
        wealth_p25=wealth_p25,
        wealth_p50=wealth_p50,
        wealth_p75=wealth_p75,
        n_sim=n_sim,
    )
end
