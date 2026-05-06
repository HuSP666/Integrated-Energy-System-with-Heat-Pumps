using CoolProp
using Printf

# 获取制冷剂的临界温度（K）
function get_critical_temperature(refrigerant)
    Tcrit = CoolProp.PropsSI("Tcrit", refrigerant)
    return Tcrit
end

# 高温级制冷循环计算
function high_stage(T_me, T_h, refrigerant, η_sh)
    # 获取临界温度
    Tcrit = get_critical_temperature(refrigerant)
    (T_me + 273.15 > Tcrit) && return (NaN, NaN, NaN, NaN, NaN, NaN)
    
    # 明确指定饱和状态参数
    P_eh = CoolProp.PropsSI("P", "T", T_me + 273.15, "Q", 1, refrigerant)
    P_ch = CoolProp.PropsSI("P", "T", T_h + 273.15, "Q", 0, refrigerant)
    
    # 直接使用Q参数获取饱和状态参数
    h4 = CoolProp.PropsSI("H", "T", T_me + 273.15, "Q", 1, refrigerant)   # 蒸发器出口（饱和蒸汽）
    h6 = CoolProp.PropsSI("H", "T", T_h + 273.15, "Q", 0, refrigerant)    # 冷凝器出口（饱和液体）
    
    # 等熵压缩计算
    s4 = CoolProp.PropsSI("S", "T", T_me + 273.15, "Q", 1, refrigerant)
    h5s = CoolProp.PropsSI("H", "P", P_ch, "S", s4, refrigerant)

    Q_eh = h4 - h6       # 单位制冷量
    w_h = (h5s - h4)/η_sh # 压缩功
    Q_ch = Q_eh + w_h     # 冷凝放热量

    return Q_eh, w_h, Q_ch, h4, h5s, h6
end

# 中温级制冷循环计算
function middle_stage(T_me, T_h, refrigerant, η_sh)
    # 获取临界温度
    Tcrit = get_critical_temperature(refrigerant)
    (T_me + 273.15 > Tcrit) && return (NaN, NaN, NaN, NaN, NaN, NaN)
    
    # 明确指定饱和状态参数
    P_eh = CoolProp.PropsSI("P", "T", T_me + 273.15, "Q", 1, refrigerant)
    P_ch = CoolProp.PropsSI("P", "T", T_h + 273.15, "Q", 0, refrigerant)
    
    # 直接使用Q参数获取饱和状态参数
    h4 = CoolProp.PropsSI("H", "T", T_me + 273.15, "Q", 1, refrigerant)   # 蒸发器出口（饱和蒸汽）
    h6 = CoolProp.PropsSI("H", "T", T_h + 273.15, "Q", 0, refrigerant)    # 冷凝器出口（饱和液体）
    
    # 等熵压缩计算
    s4 = CoolProp.PropsSI("S", "T", T_me + 273.15, "Q", 1, refrigerant)
    h5s = CoolProp.PropsSI("H", "P", P_ch, "S", s4, refrigerant)

    Q_eh = h4 - h6       # 单位制冷量
    w_h = (h5s - h4)/η_sh # 压缩功
    Q_ch = Q_eh + w_h     # 冷凝放热量

    return Q_eh, w_h, Q_ch, h4, h5s, h6
end

# 低温级制冷循环计算
function low_stage(T_e, T_mc, refrigerant, η_sl)
    # 获取临界温度并转换回°C
    Tcrit = get_critical_temperature(refrigerant) - 273.15
    
    # 温度有效性检查
    (T_mc > Tcrit) && return (NaN, NaN, NaN, NaN, NaN)
    
    # 明确指定饱和状态参数
    P_el = CoolProp.PropsSI("P", "T", T_e + 273.15, "Q", 1, refrigerant)
    P_cl = CoolProp.PropsSI("P", "T", T_mc + 273.15, "Q", 0, refrigerant)
    
    # 直接使用Q参数获取饱和状态参数
    h1 = CoolProp.PropsSI("H", "T", T_e + 273.15, "Q", 1, refrigerant)
    h3 = CoolProp.PropsSI("H", "T", T_mc + 273.15, "Q", 0, refrigerant)
    
    # 等熵压缩计算
    s1 = CoolProp.PropsSI("S", "T", T_e + 273.15, "Q", 1, refrigerant)
    h2s = CoolProp.PropsSI("H", "P", P_cl, "S", s1, refrigerant)

    Q_el = h1 - h3       # 单位制冷量
    w_l = (h2s - h1)/η_sl # 压缩功
    Q_cl = Q_el + w_l     # 冷凝放热量

    return Q_el, Q_cl, h1, h2s, h3
end

# 计算复叠系统的总COP
function calculate_COP(T_me, T_h, T_e, ΔT, refrigerant1, refrigerant2, η_sh, η_sl)
    T_mc = T_me + ΔT 
    
    # 有效性检查
    (T_me < T_e || T_mc > T_h) && return -Inf
    
    # 高温级有效性检查
    Q_eh, w_h, Q_ch, h4, h5s, h6 = high_stage(T_me, T_h, refrigerant1, η_sh)
    any(isnan, (Q_eh, w_h, Q_ch)) && return -Inf
    
    # 低温级有效性检查
    Q_el, Q_cl, h1, h2s, h3 = low_stage(T_e, T_mc, refrigerant2, η_sl)
    any(isnan, (Q_el, Q_cl)) && return -Inf

    # 热平衡检查
    (Q_eh <= 0 || Q_cl <= 0) && return -Inf
    q_ratio = Q_cl / Q_eh

    # 总功和制冷量计算
    q_ml = 1.0  # kg/s
    q_mh = q_ml * q_ratio
    W_total = q_ml * (h2s - h1) / η_sl + q_mh * (h5s - h4) / η_sh
    Q_total = q_ml * Q_el

    W_total > 0 ? Q_total / W_total : -Inf
end

# 优化COP
function optimize_COP(T_h, T_e, refrigerant1, refrigerant2, η_sh, η_sl, ΔT, step)
    best_COP, best_T = -Inf, T_e
    Tcrit_low = get_critical_temperature(refrigerant2) - 273.15  # 低温级临界温度(°C)
    
    # 计算有效搜索范围
    max_T_me = min(T_h - ΔT, Tcrit_low - ΔT - 0.1)
    if max_T_me < T_e
        error("Invalid parameter combination: T_e=$T_e, ΔT=$ΔT, Tcrit_low=$Tcrit_low")
    end

    for T_me in T_e:step:max_T_me 
        COP = calculate_COP(T_me, T_h, T_e, ΔT, refrigerant1, refrigerant2, η_sh, η_sl)
        if COP > best_COP 
            best_COP, best_T = COP, T_me
        end
    end
    
    if best_COP == -Inf
        error("没有找到有效的COP。请检查输入条件。")
    end

    return best_COP, best_T, best_T + ΔT
end

# 主函数
function main()
    T_h = 40    # 高温级冷凝温度 (°C)
    T_e = -20   # 低温级蒸发温度 (°C)
    ΔT = 15     # 中间换热温差
    
    # 制冷剂参数
    refrigerant1 = "R134a"
    refrigerant2 = "R23"
    η_sh = η_sl = 0.85
    
    # 自动获取临界温度并验证
    Tcrit_R23 = get_critical_temperature(refrigerant2) - 273.15
    @printf("R23临界温度: %.2f°C\n", Tcrit_R23)

    (T_e + ΔT > Tcrit_R23) && error("低温级最高温度超过制冷剂临界温度")
    
    # 优化计算
    best_COP, best_T_me, best_T_mc = optimize_COP(T_h, T_e, refrigerant1, refrigerant2, η_sh, η_sl, ΔT, 1)
    
    # 结果输出
    @printf("\n优化结果：\n")
    @printf("最佳COP: %.4f\n", best_COP)
    @printf("中间蒸发温度: %.1f°C\n", best_T_me)
    @printf("低温级冷凝温度: %.1f°C\n", best_T_mc)
    @printf("温度有效性验证：\n")
    @printf(" 高温级冷凝温度：%.1f°C (R134a临界温度：101.5°C)\n", T_h)
    @printf(" 低温级冷凝温度：%.1f°C (R23临界温度：%.1f°C)\n", best_T_mc, Tcrit_R23)
end

main()