module Pump3StageAX
ENV["GKS_ENCODING"] = "utf-8" # 设置绘图编码

using CoolProp
using Printf
using Statistics
using Plots

function get_critical_temperature(refrigerant)
    CoolProp.PropsSI("Tcrit", refrigerant)
end

function stage_calculation(T_evap, T_cond, refrigerant, η_comp, stage_type)
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

function run_optimization(T_low_evap, T_high_cond, η_comps, ΔT_bounds, refrigerants_list)
    results = []  # 用于存储每组制冷剂的优化结果
    for refrigerants in refrigerants_list
        best_cop, (ΔT1_opt, ΔT2_opt) = optimize_three_stage(
            T_low_evap = T_low_evap,
            T_high_cond = T_high_cond,
            refrigerants = refrigerants,
            η_comps = η_comps,
            ΔT_bounds = ΔT_bounds
        )
        push!(results, (refrigerants, best_cop, ΔT1_opt, ΔT2_opt))
    end
    return results
end

function plot_cop_heatmap(ΔT1_values, ΔT2_values, cop_values)
    heatmap(
        ΔT1_values, ΔT2_values, cop_values, xlabel="ΔT1 (°C)", ylabel="ΔT2 (°C)", 
        title="COP vs ΔT1 and ΔT2", color=:viridis, clims=(0, maximum(cop_values)), c=:viridis
    )
    savefig("cop_heatmap.png")
end

function heatStorage_inORout(hourlyTariff,heatStorage,heatStorageCapacity,hour,tag)
    # 【有待优化】添加存储系统的相关计算和逻辑,设放热输出heatStorageSaveRate或1，蓄热输出-1，关闭输出0
    Tariff_average = mean(hourlyTariff[1:24])
    if hourlyTariff[hour] < Tariff_average
        if heatStorage < heatStorageCapacity
            return -1
        else
            return 0
        end
    else
        if heatStorage > 0
            if tag == 1
                return 1
            else
                return heatStorageSaveRate
            end
        else
            return 0
        end
    end
end

function pumpWithStorage_dailyCost(hourlyTariff, best_cop, workingHours, heatConsumptionPower,heatStoragePower,heatStorage,heatStorageCapacity,heatPumpStartTime,heatPumpStopTime)
    total_cost = 0.0
    if workingHours+heatPumpStartTime+heatPumpStopTime>24
        #全天运行模式
        for hour in 1:24
            total_cost += hourlyTariff[hour] * (heatConsumptionPower / best_cop - heatStorage_inORout(hourlyTariff,heatStorage,heatStorageCapacity,hour,0) * heatStoragePower)
            heatStorage -= heatStorage_inORout(hourlyTariff,heatStorage,heatStorageCapacity,hour,1) * heatStoragePower
            if heatStorage < 0
                heatStorage = 0
            elseif heatStorage > heatStorageCapacity
                heatStorage = heatStorageCapacity
            end
            push!(RunPumpWithStorage,heatConsumptionPower) 
            push!(RunStorage, heatStorage_inORout(hourlyTariff,heatStorage,heatStorageCapacity,hour,1) * heatStoragePower)
            push!(CertainStorage, heatStorage)
        end
    else
        #分段运行模式
        for hour in 1:24
            if hour in workingStartHour : (workingHours + workingStartHour - 1)
                total_cost += hourlyTariff[hour] * (heatConsumptionPower / best_cop - heatStorage_inORout(hourlyTariff,heatStorage,heatStorageCapacity,hour,0) * heatStoragePower)
                heatStorage -= heatStorage_inORout(hourlyTariff,heatStorage,heatStorageCapacity,hour,1) * heatStoragePower
                if heatStorage < 0
                    heatStorage = 0
                elseif heatStorage > heatStorageCapacity
                    heatStorage = heatStorageCapacity
                end
                push!(RunPumpWithStorage,heatConsumptionPower) 
                push!(RunStorage, heatStorage_inORout(hourlyTariff,heatStorage,heatStorageCapacity,hour,1) * heatStoragePower)
                push!(CertainStorage, heatStorage)
            else
                if heatStorage - heatStorageLossPower > 0
                    heatStorage -= heatStorageLossPower
                    push!(RunStorage, heatStorageLossPower)
                else
                    push!(RunStorage, 0)
                end
                push!(RunPumpWithStorage,0) 
                push!(CertainStorage, heatStorage)
            end
        end
        total_cost += hourlyTariff[workingStartHour+workingHours] * heatConsumptionPower / best_cop * heatPumpStopTime
        total_cost += hourlyTariff[workingStartHour] * heatConsumptionPower / best_cop * heatPumpStartTime
    end
    return total_cost
end

function onlyPump_dailyCost(hourlyTariff, best_cop, workingHours,heatDemandPower,heatPumpStartTime,heatPumpStopTime)
    total_cost = 0.0
    if workingHours+heatPumpStartTime+heatPumpStopTime>24.0
        #全天运行模式
        for hour in 1:24
            total_cost += hourlyTariff[hour] * heatDemandPower / best_cop
            push!(RunOnlyPump,heatDemandPower)
        end
    else
        #分段运行模式
        for hour in 1:24
            if hour in workingStartHour : (workingHours + workingStartHour - 1)
                total_cost += hourlyTariff[hour] * heatDemandPower / best_cop
                push!(RunOnlyPump,heatDemandPower)
            else
                push!(RunOnlyPump,0) 
            end
        end
        total_cost += hourlyTariff[workingStartHour+workingHours] * heatDemandPower / best_cop * heatPumpStopTime
        total_cost += hourlyTariff[workingStartHour] * heatDemandPower / best_cop * heatPumpStartTime
    end
    return total_cost
end

begin
    # 参数定义
    T_low_evap = -45    # 低温级蒸发温度 (°C)
    T_high_cond = 40    # 高温级冷凝温度 (°C)
    η_comps = [0.82, 0.85, 0.88]
    ΔT_bounds = [5.0, 15.0, 5.0, 15.0]  # ΔT1范围，ΔT2范围
    refrigerants_list = [    # 成组修改制冷剂组合，最少3个
        ["R23", "R134a", "R404A"],
        ["R32", "R125", "R410A"],
        ["R290", "R600a", "R717"]
    ]

    # 执行优化，找到最大COP的结果，再进行排序
    results = run_optimization(T_low_evap, T_high_cond, η_comps, ΔT_bounds, refrigerants_list)
    sorted_results = sort(results, by = x -> x[2], rev = true)
    # 输出最佳和所有结果
    @printf("最佳制冷剂组合: %s\n", join(sorted_results[1][1], ", "))
    @printf("最大COP: %.3f", sorted_results[1][2])
    @printf("（后附所有优化结果比较）\n")
    for (refrigerants, best_cop, ΔT1_opt, ΔT2_opt) in sorted_results
        @printf("\n制冷剂组合: %s\n", join(refrigerants, ", "))
        @printf("最佳COP: %.3f\n", best_cop)
        @printf("优化中间温差 ΔT1=%.1f°C，ΔT2=%.1f°C\n", ΔT1_opt, ΔT2_opt)
        @printf("对应低温级冷凝温度：%.1f°C\n", T_low_evap + ΔT1_opt)
        @printf("对应中温级冷凝温度：%.1f°C\n", T_high_cond - ΔT2_opt)
    end

    # 绘制COP随中间温差的变化
    ΔT1_values = ΔT_bounds[1]:0.1:ΔT_bounds[2]
    ΔT2_values = ΔT_bounds[3]:0.1:ΔT_bounds[4]
    cop_values = zeros(length(ΔT1_values), length(ΔT2_values))
    for (i, ΔT1) in enumerate(ΔT1_values)
        for (j, ΔT2) in enumerate(ΔT2_values)
            cop_values[i, j] = three_stage_system(
                T_low_evap, T_low_evap + ΔT1, T_high_cond - ΔT2, sorted_results[1][1], η_comps, ΔT1, ΔT2
            )
        end
    end
    plot_cop_heatmap(ΔT1_values, ΔT2_values, cop_values)
    
    # 定义电价向量
    hourlyTariff = zeros(24)
	hourlyTariff[1:7] .= 0.3340
	hourlyTariff[8:11] .= 0.7393
	hourlyTariff[12:14] .= 1.2360
	hourlyTariff[15:18] .= 0.7393
	hourlyTariff[19:23] .= 1.2360
	hourlyTariff[24] = 0.3340
    # 工作记录
    RunOnlyPump = []
    RunStorage = []
    RunPumpWithStorage = []
    CertainStorage = []
    # 运行参数
    heatStorageCapacity = 4.5    # 蓄热器容量，假设损耗发生在储存和放热时（而不是蓄热过程）
    heatStorage = 0.0    # 蓄热器实时蓄热，初始值为0
	heatPumpServiceCoff = 1.0    # 热泵服务系数，用于计算实际的工作性能，默认为1.0
    heatPumpStartTime = 0.5    # 热泵启动耗时,仅小于1时可正常使用
    heatPumpStopTime = 0.5    # 热泵停止耗时,仅小于1时可正常使用
	workingStartHour = 0    # 生产开始时间
	workingHours = 24    # 每日工作小时数【非24小时的情况未经复测】
	heatConsumptionPower = 4.3    # 热泵产生功率
    heatDemandPower = 4.2    # 热需求功率
    heatStorageLossPower = 0.1    # 蓄热器非工作损耗功率
    heatStorageSaveRate = 0.95    # 蓄热器储热率
    heatStoragePower = 0.5    # 蓄热器功率

    # 计算前三名热泵(+蓄热)系统的每日最优成本
    for i in 1:3
        best_cop = sorted_results[i][2] * heatPumpServiceCoff
        oPdC=onlyPump_dailyCost(hourlyTariff, best_cop, workingHours,heatDemandPower,heatPumpStartTime,heatPumpStopTime)
        pWSdC=pumpWithStorage_dailyCost(
            hourlyTariff, best_cop, workingHours, heatConsumptionPower,heatStoragePower,heatStorage,heatStorageCapacity,heatPumpStartTime,heatPumpStopTime
            )
        if i == 1
            @printf("因此, 生成图像：")
            time = 1:24
            plot(time, RunOnlyPump, label="Only Pump", xlabel="T(h)", ylabel="P(kW)", title="Pump(&Storage) Run Situation")
            plot!(time, RunPumpWithStorage, label="Pump With Storage")
            plot!(time, RunStorage, label="Storage P(kW)")
            plot!(time, CertainStorage, label="Storage(kWh)", ylabel="P(kW) or Storage(kWh)")
            savefig("system_performance.png")
        end
        @printf("选择制冷剂: %s时, 优化运营成本为——\n", join(sorted_results[i][1], ", "))
        @printf("仅热泵系统: %.3f元/天, ", oPdC)
        @printf("热泵+蓄热系统: %.3f元/天\n", pWSdC)
    end

end # begin

end # module