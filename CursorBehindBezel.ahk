#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Forces Windows to handle true pixel coordinates across different screen scalings
DllCall("SetThreadDpiAwarenessContext", "ptr", -3, "ptr")

; ==========================================
; GLOBAL DYNAMIC CONFIGURATION STORAGE
; ==========================================
^+e::ToggleSetupMenu() ; Ctrl + Shift + E to configure

global EdgeConfig := Map() ; Maps "M[Number]_[Edge]" -> Configuration object
global ConfigGui := "", guiOpen := false
global Overlays := Map()
global WinNumberToAhkIndex := Map() ; Maps Windows Monitor Number -> AHK Loop Index

; Dynamically sets up profiles matching true Windows numbering schemas
InitializeUniversalDefaults() {
    global EdgeConfig, WinNumberToAhkIndex
    totalMonitors := MonitorGetCount()
    
    loop totalMonitors {
        ahkIndex := A_Index
        MonitorGet(ahkIndex, &ML, &MT, &MR, &MB)
        mW := MR - ML, mH := MB - MT
        
        ; Query the Windows system display engine name (e.g., "\\.\DISPLAY1")
        sysName := MonitorGetName(ahkIndex)
        winNum := ahkIndex ; Safety fallback
        
        ; Parse out the literal digits from the display name to match Windows Settings
        if (RegExMatch(sysName, "\d+", &match)) {
            winNum := Integer(match[0])
        }
        
        ; Map the relationship so the menu draws numbers identically to Windows Settings
        WinNumberToAhkIndex[winNum] := ahkIndex
        
        ; Register all 4 edges dynamically using the core hardware identity
        EdgeConfig["M" ahkIndex "_L"] := {E:0, W:2, L:mH, O:0}
        EdgeConfig["M" ahkIndex "_R"] := {E:0, W:2, L:mH, O:0}
        EdgeConfig["M" ahkIndex "_T"] := {E:0, W:2, L:mW, O:0}
        EdgeConfig["M" ahkIndex "_B"] := {E:0, W:2, L:mW, O:0}
    }
    
    ; AUTOMATIC PAIRING ENGINE: Scans for touching edges and activates them out-of-the-box
    loop totalMonitors {
        m1 := A_Index
        MonitorGet(m1, &L1, &T1, &R1, &B1)
        
        loop totalMonitors {
            m2 := A_Index
            if (m1 == m2)
                continue
            MonitorGet(m2, &L2, &T2, &R2, &B2)
            
            ; Auto-detect Side-by-Side intersections (Right of M1 touches Left of M2)
            if (Abs(R1 - L2) <= 5 && !(B1 < T2 || T1 > B2)) {
                EdgeConfig["M" m1 "_R"].E := 1
                EdgeConfig["M" m2 "_L"].E := 1
            }
            ; Auto-detect Stacked intersections (Bottom of M1 touches Top of M2)
            if (Abs(B1 - T2) <= 5 && !(R1 < L2 || L1 > R2)) {
                EdgeConfig["M" m1 "_B"].E := 1
                EdgeConfig["M" m2 "_T"].E := 1
            }
        }
    }
}
InitializeUniversalDefaults()

SetTimer(CheckAllEdges, 30)

CheckAllEdges() {
    CoordMode "Mouse", "Screen"
    static isHidden := false
    atEdge := false
    MouseGetPos &x, &y
    
    loop MonitorGetCount() {
        m := A_Index
        MonitorGet(m, &ML, &MT, &MR, &MB)
        prefix := "M" m "_"
        
        ; Left Edge Execution Field
        cfg := EdgeConfig[prefix "L"]
        if (cfg.E && x >= ML && x < ML + cfg.W && y >= MT + cfg.O && y <= MT + cfg.O + cfg.L)
            atEdge := true
            
        ; Right Edge Execution Field
        cfg := EdgeConfig[prefix "R"]
        if (!atEdge && cfg.E && x < MR && x >= MR - cfg.W && y >= MT + cfg.O && y <= MT + cfg.O + cfg.L)
            atEdge := true
            
        ; Top Edge Execution Field
        cfg := EdgeConfig[prefix "T"]
        if (!atEdge && cfg.E && y >= MT && y < MT + cfg.W && x >= ML + cfg.O && x <= ML + cfg.O + cfg.L)
            atEdge := true
            
        ; Bottom Edge Execution Field
        cfg := EdgeConfig[prefix "B"]
        if (!atEdge && cfg.E && y < MB && y >= MB - cfg.W && x >= ML + cfg.O && x <= ML + cfg.O + cfg.L)
            atEdge := true
            
        if (atEdge)
            break
    }
    
    if (atEdge && !isHidden) {
        SystemCursor("Hide"), isHidden := true
    } else if (!atEdge && isHidden) {
        SystemCursor("Show"), isHidden := false
    }
}

; ==========================================
; DYNAMIC COLUMNS SETUP MENU GUI
; ==========================================
ToggleSetupMenu() {
    global ConfigGui, guiOpen, EdgeConfig, Overlays, WinNumberToAhkIndex
    if (guiOpen) {
        SaveAndCloseSetup()
        return
    }
    
    numMonitors := MonitorGetCount()
    guiWidth := (numMonitors * 330) + 20
    if (guiWidth > A_ScreenWidth - 50)
        guiWidth := A_ScreenWidth - 50
        
    ConfigGui := Gui("+AlwaysOnTop", "Universal Multi-Bezel Configurator")
    ConfigGui.OnEvent("Close", (*) => SaveAndCloseSetup())
    ConfigGui.SetFont("S9")
    
    colCount := 0
    
    ; Loop through the mapped numbers sequentially to sort columns by true Windows identities
    loop 10 {
        winNum := A_Index
        if (!WinNumberToAhkIndex.Has(winNum))
            continue
            
        ahkIndex := WinNumberToAhkIndex[winNum]
        MonitorGet(ahkIndex, &ML, &MT, &MR, &MB)
        mW := MR - ML, mH := MB - MT
        prefix := "M" ahkIndex "_"
        
        colCount++
        colX := 15 + ((colCount - 1) * 330)
        
        ; FIX: Displays the exact monitor digit assigned by the operating system layout 
        ConfigGui.SetFont("S10 Bold")
        ConfigGui.Add("Text", "x" colX " y10", "Monitor #" winNum) 
        ConfigGui.SetFont("S9")
        
        edges := ["Left", "Right", "Top", "Bottom"]
        loop edges.Length {
            eIdx := A_Index, eName := edges[eIdx], eKey := SubStr(eName, 1, 1)
            cfgKey := prefix eKey
            cfg := EdgeConfig[cfgKey]
            maxLen := (eIdx <= 2) ? mH : mW
            maxOff := maxLen - 50
            yOff := 35 + ((eIdx - 1) * 115)
            
            ConfigGui.Add("CheckBox", "x" colX " y" yOff " vCB_" cfgKey " Checked" cfg.E, "Enable " eName " Edge").OnEvent("Click", OnLiveAdjust)
            ConfigGui.Add("Text", "x" colX " y" (yOff+22) " w75", "Thickness:")
            ConfigGui.Add("Slider", "x" (colX+75) " y" (yOff+20) " w230 vW_" cfgKey " Range1-30 ToolTip", cfg.W).OnEvent("Change", OnLiveAdjust)
            ConfigGui.Add("Text", "x" colX " y" (yOff+52) " w75", "Active Span:")
            ConfigGui.Add("Slider", "x" (colX+75) " y" (yOff+50) " w230 vL_" cfgKey " Range50-" maxLen " ToolTip", cfg.L).OnEvent("Change", OnLiveAdjust)
            ConfigGui.Add("Text", "x" colX " y" (yOff+82) " w75", "Position:")
            ConfigGui.Add("Slider", "x" (colX+75) " y" (yOff+80) " w230 vO_" cfgKey " Range0-" maxOff " ToolTip", cfg.O).OnEvent("Change", OnLiveAdjust)
        }
    }
    
    UpdateVisualBars()
    btnX := (guiWidth / 2) - 100
    ConfigGui.Add("Button", "x" btnX " y505 w200 h30 Default", "Save Settings").OnEvent("Click", (*) => SaveAndCloseSetup())
    ConfigGui.Show("w" guiWidth " h545 NoActivate")
    guiOpen := true
}

OnLiveAdjust(*) {
    global ConfigGui, EdgeConfig
    loop MonitorGetCount() {
        m := A_Index, prefix := "M" m "_"
        for eKey in ["L", "R", "T", "B"] {
            cfgKey := prefix eKey
            EdgeConfig[cfgKey].E := ConfigGui["CB_" cfgKey].Value
            EdgeConfig[cfgKey].W := ConfigGui["W_" cfgKey].Value
            EdgeConfig[cfgKey].L := ConfigGui["L_" cfgKey].Value
            EdgeConfig[cfgKey].O := ConfigGui["O_" cfgKey].Value
        }
    }
    UpdateVisualBars()
}

UpdateVisualBars() {
    global Overlays, EdgeConfig
    for k, obj in Overlays
        obj.Destroy()
    Overlays := Map()
    
    loop MonitorGetCount() {
        m := A_Index, prefix := "M" m "_"
        MonitorGet(m, &ML, &MT, &MR, &MB)
        
        for eKey in ["L", "R", "T", "B"] {
            cfgKey := prefix eKey
            cfg := EdgeConfig[cfgKey]
            if (!cfg.E)
                continue
                
            bar := Gui("-Caption +AlwaysOnTop +E0x20 +ToolWindow")
            bar.Opt("-DPIScale")
            bar.BackColor := "FF0000"
            
            if (eKey == "L") {
                bar.Show("X" ML " Y" (MT + cfg.O) " W" cfg.W " H" cfg.L " NoActivate")
            } else if (eKey == "R") {
                bar.Show("X" (MR - cfg.W) " Y" (MT + cfg.O) " W" cfg.W " H" cfg.L " NoActivate")
            } else if (eKey == "T") {
                bar.Show("X" (ML + cfg.O) " Y" MT " W" cfg.L " H" cfg.W " NoActivate")
            } else if (eKey == "B") {
                bar.Show("X" (ML + cfg.O) " Y" (MB - cfg.W) " W" cfg.L " H" cfg.W " NoActivate")
            }
            WinSetTransparent(120, bar)
            Overlays[cfgKey] := bar
        }
    }
}

SaveAndCloseSetup() {
    global ConfigGui, Overlays, guiOpen
    if (ConfigGui != "")
        ConfigGui.Destroy(), ConfigGui := ""
    for k, obj in Overlays
        obj.Destroy()
    Overlays := Map(), guiOpen := false
}

SystemCursor(cmd) {
    static visible := true, c := Map()
    static sys_cursors := StrSplit("32512,32513,32514,32515,32516,32642,32643,32644,32645,32646,32648,32649,32650", ",")
    if (!c.Count) {
        for id in sys_cursors {
            h_cursor := DllCall("LoadCursor", "Ptr", 0, "Ptr", Integer(id))
            h_default := DllCall("CopyImage", "Ptr", h_cursor, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0)
            h_blank := DllCall("CreateCursor", "Ptr", 0, "Int", 0, "Int", 0, "Int", 32, "Int", 32, "Ptr", Buffer(32*4, 0xFF), "Ptr", Buffer(32*4, 0))
            c[Integer(id)] := {default: h_default, blank: h_blank}
        }
    }
    switch cmd {
        case "Show": visible := true
        case "Hide": visible := false
        default: return
    }
    for id, handles in c {
        h_cursor := DllCall("CopyImage", "Ptr", visible ? handles.default : handles.blank, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0)
        DllCall("SetSystemCursor", "Ptr", h_cursor, "UInt", id)
    }
}
OnExit (*) => SystemCursor("Show")
