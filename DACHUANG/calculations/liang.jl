
# 工质选择核心函数
function select_refrigerant(Te, Tc; candidates=["water", "R245fa", "R134a", "Ammonia"])
        # 转换为开尔文温度
        Te_k = Te + 273.15
        Tc_k = Tc + 273.15
        required_Tcrit = max(Te_k, Tc_k)
        
        # 工质有效性一次验证
        function is_valid(refrig)
            try
                Tcrit = CoolProp.PropsSI("TCRIT", refrig)
                return Tcrit >= required_Tcrit
            catch
                return false
            end
        end
        
        for refrig in candidates
            if is_valid(refrig)
                # 二次验证实际工况是否可行
                try
                    CoolProp.PropsSI("P","T",Te_k,"Q",1,refrig)
                    CoolProp.PropsSI("P","T",Tc_k,"Q",1,refrig)
                    return refrig
                catch
                    continue
                end
            end
        end
        error("No valid refrigerant found. Required Tcrit ≥ $(round(required_Tcrit-273.15,digits=1))°C")
    end
    