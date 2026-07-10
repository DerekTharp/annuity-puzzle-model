using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

@testset "Hazard normalization" begin
    p_base = ModelParams(age_start=65, age_end=110)
    base_surv = build_lockwood_survival(p_base)
    common = (gamma=2.5, beta=0.97, r=0.02, stochastic_health=true,
              n_health_states=3, health_mortality_corr=true,
              hazard_mult=[0.50, 1.0, 3.75], age_start=65, age_end=110)

    @testset "flag off is bit-identical to legacy" begin
        p_off = ModelParams(; common..., hazard_normalize=false)
        p_leg = ModelParams(; common...)
        @test build_health_survival(base_surv, p_off) ==
              build_health_survival(base_surv, p_leg)
    end

    @testset "population-weighted survival matches the table" begin
        p_on = ModelParams(; common..., hazard_normalize=true)
        sh = build_health_survival(base_surv, p_on; psi_override=1.0)
        trans = build_all_health_transitions(p_on)
        pi_h = copy(p_on.initial_health_shares); pi_h ./= sum(pi_h)
        for t in 1:(p_on.T - 1)
            mixed = sum(pi_h[h] * sh[t, h] for h in 1:3)
            @test isapprox(mixed, base_surv[t]; atol=1e-9)
            alive = [pi_h[h] * sh[t, h] for h in 1:3]
            nxt = zeros(3)
            for h in 1:3, h2 in 1:3
                nxt[h2] += alive[h] * trans[t][h, h2]
            end
            pi_h = nxt ./ sum(nxt)
        end
        @test sh[p_on.T, :] == zeros(3)
    end

    @testset "relative hazards and pessimism preserved" begin
        p_on = ModelParams(; common..., hazard_normalize=true,
                           survival_pessimism=0.96)
        sh = build_health_survival(base_surv, p_on)
        sh_obj = build_health_survival(base_surv, p_on; psi_override=1.0)
        for t in 1:(p_on.T - 1)
            @test sh_obj[t, 1] >= sh_obj[t, 2] >= sh_obj[t, 3]
            for h in 1:3
                @test isapprox(sh[t, h], clamp(sh_obj[t, h] * 0.96, 0.0, 1.0);
                               atol=1e-12)
            end
        end
        # Hazard-space normalization keeps survival strictly below one at
        # every interior age by construction.
        @test all(sh_obj[t, 1] < 1.0 for t in 1:(p_on.T - 1))
    end
end

println("Hazard normalization tests passed.")
