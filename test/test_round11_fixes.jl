# Terminal safety-net SDU classification and pairwise minimum-purchase merge.
#
# 1. terminal_value: when terminal resources are raised to the consumption
#    floor, the government top-up must be classified as income for SDU
#    accounting (inc = c_floor - W, the Medicaid convention), not as
#    portfolio-financed consumption. Under lambda_w = 1 the classification is
#    irrelevant (flow_utility_sdu short-circuits), so the nine-channel game
#    is unaffected by construction.
#
# 2. run_pairwise_interactions: the second-channel merge must carry
#    min_purchase. Under a deliberately binding purchase floor, every pair
#    that includes the Loads channel must predict zero ownership, matching
#    the exact-subset coalition in which the floor forbids all purchases.

using Test

if !isdefined(Main, :AnnuityPuzzle)
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
using .AnnuityPuzzle: terminal_value, flow_utility_sdu, utility,
    consumption_weight, health_utility_weight

@testset "Terminal safety-net SDU classification" begin
    # Floor binds: W + A + ss < c_floor.
    W, A, ss = 800.0, 300.0, 900.0
    cf = 5_000.0
    t, ih = 30, 2

    p_sdu = ModelParams(lambda_w=0.625, theta=0.0, c_floor=cf)
    V, c_star = terminal_value(W, A, ss, p_sdu, t, ih)
    @test c_star ≈ cf

    # Correct classification: portfolio drawdown = W; income = c_floor - W.
    w_scale = consumption_weight(t, p_sdu.consumption_decline) *
              health_utility_weight(ih, p_sdu)
    c_eff_correct = (cf - W) + p_sdu.lambda_w * W
    @test V ≈ w_scale * utility(c_eff_correct, p_sdu.gamma) atol = 1e-10

    # The defective classification (inc = A + ss) treats the top-up as
    # portfolio-financed and must NOT be reproduced.
    c_eff_defect = (A + ss) + p_sdu.lambda_w * (cf - A - ss)
    @test !(V ≈ w_scale * utility(c_eff_defect, p_sdu.gamma))
    @test c_eff_correct > c_eff_defect  # more income-classified => higher c_eff

    # lambda_w = 1: classification irrelevant; value equals plain utility of
    # the floor. Nine-channel invariance follows from this short-circuit.
    p_neutral = ModelParams(lambda_w=1.0, theta=0.0, c_floor=cf)
    V1, _ = terminal_value(W, A, ss, p_neutral, t, ih)
    w_scale1 = consumption_weight(t, p_neutral.consumption_decline) *
               health_utility_weight(ih, p_neutral)
    @test V1 ≈ w_scale1 * utility(cf, p_neutral.gamma) atol = 1e-10

    # Floor slack: inc stays A + ss regardless of lambda_w.
    W2 = 20_000.0
    p_slack = ModelParams(lambda_w=0.625, theta=0.0, c_floor=cf)
    V2, c2 = terminal_value(W2, A, ss, p_slack, t, ih)
    cash2 = W2 + A + ss
    @test c2 ≈ cash2
    c_eff_slack = (A + ss) + p_slack.lambda_w * (cash2 - A - ss)
    w_scale2 = consumption_weight(t, p_slack.consumption_decline) *
               health_utility_weight(ih, p_slack)
    @test V2 ≈ w_scale2 * utility(c_eff_slack, p_slack.gamma) atol = 1e-10
end

@testset "Pairwise merge carries min_purchase (binding-floor parity)" begin
    p_tmp = ModelParams(age_start=65, age_end=100)
    base_surv = production_base_survival(p_tmp)

    # Small population, coarse grid: speed over level accuracy. The floor is
    # set above W_max so ANY purchase is contractually forbidden; the only
    # loads friction is a mild MWR wedge (no fixed cost), so absent the
    # floor these pairs annuitize and the test discriminates.
    pop = [50_000.0 0.0 65.0 2.0;
           150_000.0 0.0 65.0 1.0;
           400_000.0 0.0 65.0 2.0]
    res = run_pairwise_interactions(base_surv, pop;
        gamma=2.5, theta=56.96, kappa=272_628.0,
        mwr_loaded=0.95, fixed_cost_val=0.0,
        min_purchase_val=10_000_000.0,
        inflation_val=0.02,
        n_wealth=12, n_annuity=5, n_alpha=11, W_max=600_000.0, n_quad=3,
        ss_levels=[15_000.0, 15_000.0, 15_000.0, 15_000.0],
        verbose=false)

    li = findfirst(==("Loads"), res.channel_names)
    @test li !== nothing
    # Isolated Loads: floor already carried since the channel config sets it.
    @test res.isolated_ownership[li] == 0.0
    # Every pair including Loads: the merge must preserve the floor, so
    # ownership is zero exactly as in the corresponding exact-subset
    # coalition (a purchase below the floor is not a contract).
    for j in eachindex(res.channel_names)
        j == li && continue
        @test res.pair_ownership[li, j] == 0.0
    end
end

println("test_round11_fixes: all passed")
