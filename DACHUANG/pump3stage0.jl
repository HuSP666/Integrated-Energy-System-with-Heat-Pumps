#三级热泵
using CoolProp
using Printf

function get_critical_temperature(refrigerant)
    CoolProp.PropsSI("Tcrit", refrigerant)
end

function stage_calculation(T_evap, T_cond, refrigerant, η_comp, stage_type)
    Tcrit = get_critical_temperature(refrigerant)
    # 温度有效性检查
    (T_evap + 273.15 > Tcrit || T_cond + 273.15 > Tcrit) && return (NaN, NaN, NaN, NaN, NaN)
    # 蒸发压力/冷凝压力计算
    P_evap = CoolProp.PropsSI("P", "T", T_evap + 273.15, "Q", 1, refrigerant)
    P_cond = CoolProp.PropsSI("P", "T", T_cond + 273.15, "Q", 0, refrigerant)
    # 状态点参数计算
    h_evap_out = CoolProp.PropsSI("H", "T", T_evap + 273.15, "Q", 1, refrigerant)
    h_cond_out = CoolProp.PropsSI("H", "T", T_cond + 273.15, "Q", 0, refrigerant)
    # 等熵压缩过程
    s_evap = CoolProp.PropsSI("S", "T", T_evap + 273.15, "Q", 1, refrigerant)
    h_comp_out_isen = CoolProp.PropsSI("H", "P", P_cond, "S", s_evap, refrigerant)
    # 实际压缩功
    w_comp = (h_comp_out_isen - h_evap_out) / η_comp
    
    # 根据级类型计算有效参数
    if stage_type == :low
        Q_cooling = h_evap_out - h_cond_out
        Q_cond = Q_cooling + w_comp
        return (Q_cooling, w_comp, Q_cond, h_evap_out, h_comp_out_isen)
    else
        Q_heating = h_evap_out - h_cond_out + w_comp
        return (Q_heating, w_comp, h_evap_out, h_comp_out_isen, NaN)
    end
end

function three_stage_system(T_low_evap, T_med_evap, T_high_cond, refrigerants, η_comps, ΔT1, ΔT2)
    # 中间温度计算
    T_low_cond = T_med_evap + ΔT1
    T_med_cond = T_high_cond - ΔT2
    # 三级循环计算
    low_stage = stage_calculation(T_low_evap, T_low_cond, refrigerants[1], η_comps[1], :low)
    med_stage = stage_calculation(T_med_evap, T_med_cond, refrigerants[2], η_comps[2], :med)
    high_stage = stage_calculation(T_med_cond, T_high_cond, refrigerants[3], η_comps[3], :high)
    # 质量流量平衡计算
    qm_low = 1.0  # 假设低温级质量流量为基准
    qm_med = qm_low * low_stage[3] / med_stage[1]
    qm_high = qm_med * med_stage[3] / high_stage[1]
    
    # 总制冷量和功耗
    total_cooling = qm_low * low_stage[1]
    total_power = qm_low*low_stage[2] + qm_med*med_stage[2] + qm_high*high_stage[2]
    
    total_power > 0 ? total_cooling / total_power : -Inf
end

function optimize_three_stage(; T_low_evap, T_high_cond, refrigerants, η_comps,  ΔT_bounds, step=0.5)
    best_cop = -Inf
    best_params = (0.0, 0.0)
    # 生成参数搜索空间
    for ΔT1 in ΔT_bounds[1]:step:ΔT_bounds[2]
        for ΔT2 in ΔT_bounds[3]:step:ΔT_bounds[4]
            T_med_evap = T_low_evap + ΔT1
            T_med_cond = T_high_cond - ΔT2
            # 有效性检查
            if T_med_evap >= T_med_cond
                continue
            end
            # 计算COP，并更新最佳参数
            cop = three_stage_system(T_low_evap, T_med_evap, T_high_cond, refrigerants, η_comps, ΔT1, ΔT2)
            if cop > best_cop
                best_cop = cop
                best_params = (ΔT1, ΔT2)
            end
        end
    end
    
    (best_cop, best_params)
end

begin
    T_low_evap = -40   # 低温级蒸发温度 (°C)
    T_high_cond = 45    # 高温级冷凝温度 (°C)
    refrigerants = ["R23", "R134a", "R404A"]
    η_comps = [0.82, 0.85, 0.88]
    ΔT_bounds = [5.0, 15.0, 5.0, 15.0]  # ΔT1范围，ΔT2范围
    
    # 执行优化
    best_cop, (ΔT1_opt, ΔT2_opt) = optimize_three_stage(
        T_low_evap = T_low_evap,
        T_high_cond = T_high_cond,
        refrigerants = refrigerants,
        η_comps = η_comps,
        ΔT_bounds = ΔT_bounds
    )
    
    # 结果输出
    @printf("优化结果：\n")
    @printf("最佳COP: %.3f\n", best_cop)
    @printf("优化中间温差 ΔT1=%.1f°C，ΔT2=%.1f°C\n", ΔT1_opt, ΔT2_opt)
    @printf("对应温度参数：\n")
    @printf("低温级冷凝温度：%.1f°C\n", T_low_evap + ΔT1_opt)
    @printf("中温级冷凝温度：%.1f°C\n", T_high_cond - ΔT2_opt)
end