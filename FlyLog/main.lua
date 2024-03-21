--[[
Release:
v0.1 2024-01-19
v0.2 2024-02-07
v0.3 2024-02-13rq
v0.4 2024-02-22 (RF2 20240218 Version)
v0.5 2024-03-21
--]]

--[[
FM:
OFF
IDLE
SPOOLUP
RECOVERY
ACTIVE
THR-OFF
LOST-HS
AUTOROT
BAILOUT
]]

--[[
Redefine telemetry
CLI:
set crsf_gps_heading_reuse = THROTTLE
set crsf_flight_mode_reuse = GOV_ADJFUNC
set crsf_gps_altitude_reuse = HEADSPEED
set crsf_gps_ground_speed_reuse = ESC_TEMP
set crsf_gps_sats_reuse = MCU_TEMP
save
]]

--Script information
local name = "FlyLog"
local LuaVersion = "v0.5"

--Variable
local CrsfField = { "RxBt", "Curr", "Alt", "Capa", "Bat%", "GSpd", "Sats", "1RSS", "2RSS", "RQly", "Hdg", "FM" }
local FportField = { "VFAS", "Curr", "RPM1", "5250", "Fuel", "EscT", "Tmp1", "RSSI", "TRSS", "TQly", "Hdg", "FM" }
local DisplayItem = { "Voltage[V]", "Current[A]", "HSpd[rpm]", "FM:" }
local TableFormat = { "%.1f", "%.1f", "%d", "%s" }
local TableField = {}

--Define
local TeleItems = 12
local FmIndex = 12
local TableHag = { 11, 10 }
local DisplayFmIndex = 4
local LogInfoLen = 22
local LogDataLen = 104
--Variable
local ModelName = ""
local ProtocolType = 0
local ValueMinMax = {}
local PowerMax = { 0, 0 }
local CapaStart = 0
local FuelStart = 0
local TableID = {}
local TimeOS = 0
local RingPos = 0
local VerifyFuel = 0
local WaitCnt = 0
local PointerPic
local FileName = ""
local FilePath = ""
local FileObj
local LogInfo = ""
local LogData = {}
local FlyNumber = 0
local SeleNumber = 0
local Second = { 0, 0, 0 }
local TotalSecond = 0
local Hours = 0
local Minutes = { 0, 0 }
local Seconds = { 0, 0 }
local PlaySpeed = 0
--Flag
local PaintColorFlag = BLACK
local SetColorFlag
local BatteryOnFlag
local InitSyncFlag
local SpoolUpFlag
local DisplayLogFlag
local WriteEnFlag
local SlidingFlag
local RingStartFlag
local RingEndFlag

local options = {
    { "TelemetryValueColor", COLOR,  BLACK },
    { "ThrottleChannel",     SOURCE, 215 }, --CH6
    { "LowVoltageValue_x10", VALUE,  216,  0, 550 },
    { "LowFuelValue",        VALUE,  0,    0, 100 }
}

local function create(zone, options)
    local widget = {
        zone = zone,
        options = options
    }
    local module = {}
    --Head speed ratio
    --local _, _, major, minor, rev, osname = getVersion()

    --Variable initialization
    SeleNumber = 1
    for i = 1, #Second do
        Second[i] = 0
    end
    TotalSecond = 0
    --Flag
    WriteEnFlag = false
    SlidingFlag = false
    RingStartFlag = false
    RingEndFlag = false

    --Model Name
    ModelName = model.getInfo().name

    --Initialize the array
    for i = 1, TeleItems - 1 do
        ValueMinMax[i] = { 0, 0, 0 }
    end
    for i = 1, TeleItems do
        TableID[i] = { 0, 0 }
    end

    --Protocol Type
    module[1] = model.getModule(0) --Internal
    module[2] = model.getModule(1) --External
    ProtocolType = 0               --CRSF
    for m = 1, 2 do
        if module[m] ~= nil then
            if module[m].Type == 6 and module[m].protocol == 64 then -- MULTIMODULE D16
                ProtocolType = 1                                     -- FPORT
                break
            end
        end
    end

    --Redefine fields
    TableField = ProtocolType == 1 and FportField or CrsfField

    --Get ID
    for k, v in pairs(TableField) do
        local TableInfo = getFieldInfo(v)
        if TableInfo ~= nil then
            TableID[k][1] = TableInfo.id
            TableID[k][2] = true
        else
            TableID[k][1] = 0;
            TableID[k][2] = false
        end
    end

    --Loading pic
    PointerPic = Bitmap.open("/WIDGETS/FlyLog/a.png")

    --log
    FileName = '[' .. ModelName .. ']' ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. ".log"
    FilePath = "/WIDGETS/FlyLog/logs/" .. FileName

    local FileInfo = fstat(FilePath)
    local ReadCnt = 1
    if FileInfo ~= nil then
        if FileInfo.size > 0 then
            FileObj = io.open(FilePath, "r")
            LogInfo = io.read(FileObj, LogInfoLen + 1)
            while true do
                LogData[ReadCnt] = io.read(FileObj, LogDataLen + 1)
                if #LogData[ReadCnt] == 0 then
                    break
                else
                    ReadCnt = ReadCnt + 1
                end
            end
            io.close(FileObj)
            --Get Total Seconds
            Hours = string.sub(LogInfo, 12, 13)
            Minutes[2] = string.sub(LogInfo, 15, 16)
            Seconds[2] = string.sub(LogInfo, 18, 19)
            --Tonumber
            TotalSecond = tonumber(string.sub(LogInfo, 12, 13)) * 3600
            TotalSecond = TotalSecond + tonumber(string.sub(LogInfo, 15, 16)) * 60
            TotalSecond = TotalSecond + tonumber(string.sub(LogInfo, 18, 19))
        end
    else
        FileObj = io.open(FilePath, "w")
        LogInfo =
            string.format("%d", getDateTime().year) .. '/' ..
            string.format("%02d", getDateTime().mon) .. '/' ..
            string.format("%02d", getDateTime().day) .. '|' ..
            "00:00:00" .. '|' ..
            "00\n"
        io.write(FileObj, LogInfo)
        io.close(FileObj)
    end

    --Parse the data
    local StrTemp = string.sub(LogInfo, 21, 23)
    if tonumber(StrTemp) ~= nil then
        FlyNumber = tonumber(StrTemp)
    end
    return widget
end

local function update(widget, options)
    widget.options = options
end

local function background(widget)
end

local function FuelPercentage(x, y, capa, number)
    local color = lcd.RGB(255 - number * 2.55, number * 2.55, 0)
    lcd.drawAnnulus(x, y, 65, 70, 0, 360, lcd.RGB(100, 100, 100))
    if number ~= 0 then
        lcd.drawAnnulus(x, y, 45, 65, (100 - number) * 3.6, 360, color)
    end
    if number ~= 100 then
        lcd.drawAnnulus(x, y, 45, 65, 0, (100 - number) * 3.6, lcd.RGB(220, 220, 220))
    end
    lcd.drawText(x + 2, y - 10, string.format("%d%%", number), CENTER + VCENTER + DBLSIZE + SetColorFlag)
    lcd.drawText(x, y + 15, string.format("%dmAh", capa), CENTER + VCENTER + SetColorFlag)
end

local function getSeleNumber(x, y, tx, ty, flyn)
    local xs = x
    local ys = y
    for d = 0, flyn - 1 do
        if d % 8 == 0 then
            xs = 12
            if d > 0 then
                ys = ys + 35
            end
        else
            xs = xs + 58
        end
        if tx > xs - 5 and tx < xs + 48 + 5 and ty > ys - 5 and ty < ys + 30 + 5 then
            return d + 1
        end
    end
    return 0
end

local function logmenu(x, y, pixels, str)
    lcd.drawBitmap(PointerPic, x + 1, y + 1)
    lcd.drawRectangle(x, y, 48, 30, PaintColorFlag, pixels)
    lcd.drawText(x + 24, y + 15, str, CENTER + VCENTER + PaintColorFlag)
end

local function displaylog(x, y, title, message, flags)
    local Extract = {}
    local DataTemp
    --Date time
    local Pos, Len = 4, 8
    Extract[1] = string.sub(message, Pos, Pos + Len - 1)
    --Flight time
    Pos = 13
    Len = 5
    Extract[2] = string.sub(message, Pos, Pos + Len - 1)
    --Capa Fuel HSpd Current Power [[Voltage EscT McuT 1RSS 2RSS RQly] MAX MIN] Throttle
    for t = 1, 18 do
        Pos = Pos + Len + 1
        if t == 2 or t == 16 or t == 17 or t == 18 then
            Len = 3
        elseif t == 4 then
            Len = 5
        else
            Len = 4
        end
        DataTemp = tonumber(string.sub(message, Pos, Pos + Len - 1))
        if t == 4 or t == 6 or t == 7 then
            Extract[t + 2] = string.format("%.1f", DataTemp)
        else
            Extract[t + 2] = string.format("%d", DataTemp)
        end
    end
    --Display
    lcd.drawFilledRectangle(x, y, 400, 155, lcd.RGB(250, 250, 250))
    lcd.drawRectangle(x, y, 400, 155, PaintColorFlag, 2)
    lcd.drawLine(x, y + 28, x + 400 - 2, y + 28, SOLID, PaintColorFlag)
    lcd.drawText(x + 5, y + 5, title, PaintColorFlag)
    lcd.drawText(x + 5, y + 30,
        "Time: " .. Extract[2] .. '\n' ..
        "Capa: " .. Extract[3] .. "[mAh]\n" ..
        "Fuel: " .. Extract[4] .. "[%]\n" ..
        "HSpd: " .. Extract[5] .. "[rpm]-" .. Extract[20] .. "[%]\n" ..
        "Current: " .. Extract[6] .. "[A]\n" ..
        "Power: " .. Extract[7] .. "[W]"
        , flags)
    lcd.drawText(x + 220, y + 30,
        "Voltage: " .. Extract[8] .. " -> " .. Extract[9] .. "[V]\n" ..
        "EscT: " .. Extract[11] .. " -> " .. Extract[10] .. "[°C]\n" ..
        "McuT: " .. Extract[13] .. " -> " .. Extract[12] .. "[°C]\n" ..
        TableField[8] .. ": " .. Extract[14] .. " -> " .. Extract[15] .. "[dB]\n" ..
        TableField[9] .. ": " .. Extract[16] .. " -> " .. Extract[17] .. "[dB]\n" ..
        TableField[10] .. ": " .. Extract[18] .. " -> " .. Extract[19] .. "[%]"
        , flags)
end

local function refresh(widget, event, touchState)
    local yOffset = 13
    local yLineHt = 48
    local xs = widget.zone.x --0
    local ys = widget.zone.y --0
    local xe = widget.zone.w --392
    local ye = widget.zone.h --168
    local GetValue
    local WidgetFlag = false
    local TouchKey
    local Protocol

    --Layout Mode
    if xe < 480 and ye < 272 then --Widget 392x168 Full 480x272
        WidgetFlag = true
        DisplayLogFlag = false
    end

    --Options
    lcd.setColor(CUSTOM_COLOR, widget.options.TelemetryValueColor)
    SetColorFlag = lcd.getColor(CUSTOM_COLOR)
    Protocol = ProtocolType == 1 and "[FPORT]" or "[CRSF]"

    --Event
    if event ~= 0 then
        if touchState then
            if event == EVT_TOUCH_FIRST and DisplayLogFlag == false then
                TouchKey = getSeleNumber(12, 25, touchState.x, touchState.y, FlyNumber)
                if TouchKey ~= 0 then
                    SeleNumber = TouchKey
                    DisplayLogFlag = true
                    playTone(100, 200, 100, PLAY_NOW, 10)
                end
            elseif event == EVT_TOUCH_BREAK and SlidingFlag then
                SlidingFlag = false
                if DisplayLogFlag then
                    DisplayLogFlag = false
                else
                    lcd.exitFullScreen()
                end
                playTone(10000, 200, 100, PLAY_NOW, -60)
            elseif event == EVT_TOUCH_TAP then
            elseif event == EVT_TOUCH_SLIDE then
                if touchState.swipeRight then
                    SlidingFlag = true
                elseif touchState.swipeLeft then
                elseif touchState.swipeUp then
                elseif touchState.swipeDown then
                else
                end
            end
        else
            if event == EVT_VIRTUAL_PREV and DisplayLogFlag == false then
                if SeleNumber > 1 then
                    SeleNumber = SeleNumber - 1
                else
                    SeleNumber = FlyNumber
                end
                playTone(200, 50, 100, PLAY_NOW)
            elseif event == EVT_VIRTUAL_NEXT and DisplayLogFlag == false then
                if SeleNumber < FlyNumber then
                    SeleNumber = SeleNumber + 1
                else
                    SeleNumber = 1;
                end
                playTone(200, 50, 100, PLAY_NOW)
            elseif event == EVT_VIRTUAL_ENTER then
                if DisplayLogFlag then
                    DisplayLogFlag = false
                else
                    DisplayLogFlag = true
                end
                playTone(100, 200, 100, PLAY_NOW, 10)
            elseif event == EVT_VIRTUAL_EXIT then
            elseif event == EVT_VIRTUAL_PREV_PAGE then
            elseif event == EVT_VIRTUAL_NEXT_PAGE then
            end
        end
    end

    --FM
    if WidgetFlag then --Widget 392x168
        xs = 0
        ys = 0
        lcd.drawText(xs, ys, name .. ' ' .. LuaVersion .. ' ' .. Protocol .. ' ' .. '[' .. ModelName .. ']',
            PaintColorFlag)
        lcd.drawText(xs + 261, ys, DisplayItem[DisplayFmIndex], PaintColorFlag)
        if TableID[FmIndex][2] then
            GetValue = getValue(TableID[FmIndex][1])
            if GetValue == 0 then
                lcd.drawText(xs + 261 + 30, ys, "No Tele", BLINK + PaintColorFlag)
                RingPos = 0
                WaitCnt = 0
                VerifyFuel = 0
                PlaySpeed = 0
                TimeOS = getTime()
                InitSyncFlag = false
                BatteryOnFlag = false
                SpoolUpFlag = false
                if RingEndFlag then
                    RingStartFlag = false
                    RingEndFlag = false
                end
            else
                --Hint
                if ProtocolType == 1 then --FPORT
                    GetValue = bit32.band(GetValue, 0x0007)
                    if GetValue == 1 then
                        lcd.drawText(xs + 261 + 30, ys, "DISARMED", PaintColorFlag)
                    elseif GetValue == 5 then
                        lcd.drawText(xs + 261 + 30, ys, "ARMED", PaintColorFlag)
                    else
                        lcd.drawText(xs + 261 + 30, ys, "ARMING", PaintColorFlag)
                    end
                else --CRSF
                    lcd.drawText(xs + 261 + 30, ys, string.format(TableFormat[DisplayFmIndex], GetValue), PaintColorFlag)
                end
                --Control
                if GetValue == "DISARMED" or GetValue == 1 then
                    if BatteryOnFlag == false then
                        if getTime() - TimeOS > 350 then
                            TimeOS = getTime()
                            InitSyncFlag = true
                            BatteryOnFlag = true
                            --Zeros
                            for i = 1, #ValueMinMax do
                                for j = 1, #ValueMinMax[i] do
                                    ValueMinMax[i][j] = 0
                                end
                            end
                            PowerMax[1] = 0
                            PowerMax[2] = 0
                        end
                    end
                    if SpoolUpFlag then
                        SpoolUpFlag = false
                        WriteEnFlag = true
                    end
                elseif SpoolUpFlag == false and (GetValue == "OFF" or GetValue == "SPOOLUP" or GetValue == 5) then
                    Second[1] = 0
                    SpoolUpFlag = true
                    --Synchronize data before starting
                    CapaStart = ValueMinMax[4][1]
                    FuelStart = ValueMinMax[5][1]
                    PowerMax[1] = 0
                    PowerMax[2] = 0
                    for s = 1, TeleItems - 1 do
                        ValueMinMax[s][2] = ValueMinMax[s][1]
                        ValueMinMax[s][3] = ValueMinMax[s][1]
                    end
                end
            end
        else
            lcd.drawText(xs + 261 + 30, ys, "No Tele", BLINK + PaintColorFlag)
        end
    end

    --Telemetry data
    for k = 1, TeleItems - 1 do
        if k == 1 then
            xs = 150
            ys = 20
        end
        if k < 4 and WidgetFlag then
            lcd.drawText(xs, ys, DisplayItem[k], PaintColorFlag)
        end
        if TableID[k][2] then
            GetValue = getValue(TableID[k][1])
            --CRSF
            if ProtocolType == 0 then
                if k == TableHag[1] then
                    GetValue = GetValue * TableHag[2];
                end
            end
            ValueMinMax[k][1] = GetValue
            if InitSyncFlag then
                ValueMinMax[k][2] = GetValue
                ValueMinMax[k][3] = GetValue
                --Ring
                if RingStartFlag == false and ValueMinMax[5][1] > 0 then
                    VerifyFuel = VerifyFuel + 1
                    if VerifyFuel > 29 then
                        WaitCnt = 0
                        RingStartFlag = true
                        RingEndFlag = false
                    end
                else
                    VerifyFuel = 0
                end
            else
                if BatteryOnFlag and GetValue ~= 0 then
                    if GetValue > ValueMinMax[k][2] then
                        ValueMinMax[k][2] = GetValue
                    elseif GetValue < ValueMinMax[k][3] then
                        ValueMinMax[k][3] = GetValue
                    end
                end
            end
            if k < 4 and WidgetFlag then
                lcd.drawText(xs, ys + yOffset, string.format(TableFormat[k], ValueMinMax[k][1]), DBLSIZE + SetColorFlag)  --Real time
                lcd.drawText(xs + 85, ys + yOffset, string.format(TableFormat[k], ValueMinMax[k][2]), SetColorFlag)       --Max
                if k == 2 then
                    lcd.drawText(xs + 85, ys + yOffset + 15, string.format("%dW", PowerMax[2]), SetColorFlag)             --Power
                elseif k == 3 then
                    if ProtocolType == 1 then                                                                             --FPORT
                        lcd.drawText(xs + 85, ys + yOffset + 15, string.format("%.f%%",
                            (getOutputValue(widget.options.ThrottleChannel - 210) + 1024) / 2048 * 100), SetColorFlag)    --Throttle [Remote control channel value]
                    else                                                                                                  --CRSF
                        lcd.drawText(xs + 85, ys + yOffset + 15, string.format("%d%%", ValueMinMax[11][1]), SetColorFlag) --Throttle [FC real-time value]
                    end
                else
                    lcd.drawText(xs + 85, ys + yOffset + 15, string.format(TableFormat[k], ValueMinMax[k][3]),
                        SetColorFlag) --Voltage Min
                end
            end
        else
            if k < 4 and WidgetFlag then
                lcd.drawText(xs, ys + yOffset, "----", DBLSIZE + SetColorFlag)
            end
        end
        ys = ys + yLineHt
    end
    --Limit RPM maximum
    ValueMinMax[3][2] = math.min(ValueMinMax[3][2], 9999)

    --Power
    PowerMax[2] = math.min(math.floor(ValueMinMax[1][1] * ValueMinMax[2][1]), 9999)
    if PowerMax[1] < PowerMax[2] then
        PowerMax[1] = PowerMax[2]
    end

    --Synchronize
    if InitSyncFlag then
        if getTime() - TimeOS > 1500 then
            InitSyncFlag = false
        end
    end

    --Timer Warning
    if SpoolUpFlag then
        Second[3] = getRtcTime()
        if Second[2] ~= Second[3] then
            Second[2] = Second[3]
            --Subtotal
            Second[1] = Second[1] + 1
            --Total
            TotalSecond = TotalSecond + 1
            --Warning
            if widget.options.LowVoltageValue_x10 ~= 0 or widget.options.LowFuelValue ~= 0 then
                if ValueMinMax[1][1] < widget.options.LowVoltageValue_x10 / 10 or ValueMinMax[5][1] < widget.options.LowFuelValue then
                    PlaySpeed = PlaySpeed + 1
                    if PlaySpeed > 2 then
                        PlaySpeed = 0
                        playFile("/WIDGETS/FlyLog/batlow.wav")
                        playHaptic(25, 50, 0)
                        playHaptic(10, 20, 1)
                    end
                else
                    PlaySpeed = 0
                end
            end
        end
    end

    --Format Timer
    Minutes[1] = string.format("%02d", math.floor(Second[1] % 3600 / 60))
    Seconds[1] = string.format("%02d", Second[1] % 3600 % 60)
    Hours = string.format("%02d", math.floor(TotalSecond / 3600))
    Minutes[2] = string.format("%02d", math.floor(TotalSecond % 3600 / 60))
    Seconds[2] = string.format("%02d", TotalSecond % 3600 % 60)

    --Display mode
    if WidgetFlag then --Widget 392x168
        xs = 0
        ys = 0
        --Dividing line
        lcd.drawLine(xs + 145, ys + 66, xe, ys + 66, SOLID, PaintColorFlag)
        lcd.drawLine(xs + 145, ys + 66 + yLineHt, xe, ys + 66 + yLineHt, SOLID, PaintColorFlag)
        lcd.drawLine(xs + 285, ys + 20, xs + 285, ye - 6, SOLID, PaintColorFlag)

        --Fuel Percentage
        if RingStartFlag and RingEndFlag == false then
            if RingPos >= ValueMinMax[5][1] then
                WaitCnt = WaitCnt + 1
                if WaitCnt > 99 then
                    RingEndFlag = true
                end
            else
                RingPos = RingPos + 1
                WaitCnt = 0
            end
        else
            if RingEndFlag then
                RingPos = ValueMinMax[5][1]
            else
                RingPos = 0
            end
        end
        FuelPercentage(xs + 70, ys + 90, ValueMinMax[4][1], RingPos)

        --Timer 48x112
        xs = 280
        ys = 20
        --T1
        lcd.drawText(xs + 12, ys, "T1", PaintColorFlag)
        lcd.drawText(xs + 45, ys, "M", PaintColorFlag)
        lcd.drawText(xs + 45 + 53, ys, "S", PaintColorFlag)
        lcd.drawText(xs + 12, ys + yOffset, Minutes[1], DBLSIZE + SetColorFlag)
        lcd.drawText(xs + 65, ys + yOffset, Seconds[1], DBLSIZE + SetColorFlag)
        --T2
        ys = ys + yLineHt
        lcd.drawText(xs + 12, ys, "T2", PaintColorFlag)
        if TotalSecond >= 3600 then
            lcd.drawText(xs + 45, ys, "H", PaintColorFlag)
            lcd.drawText(xs + 45 + 53, ys, "M", PaintColorFlag)
            lcd.drawText(xs + 12, ys + yOffset, Hours, DBLSIZE + SetColorFlag)
            lcd.drawText(xs + 65, ys + yOffset, Minutes[2], DBLSIZE + SetColorFlag)
        else
            lcd.drawText(xs + 45, ys, "M", PaintColorFlag)
            lcd.drawText(xs + 45 + 53, ys, "S", PaintColorFlag)
            lcd.drawText(xs + 12, ys + yOffset, Minutes[2], DBLSIZE + SetColorFlag)
            lcd.drawText(xs + 65, ys + yOffset, Seconds[2], DBLSIZE + SetColorFlag)
        end
        --Number of flights
        ys = ys + yLineHt - 18
        lcd.drawText(xs + 20, ys, string.format("%02d", FlyNumber), XXLSIZE + SetColorFlag)
        lcd.drawText(xs + 45 + 53, ys + 18, "N", PaintColorFlag)
    else --Full 480x272
        --logFlie
        lcd.drawText(12, 2,
            FileName .. "  " ..
            Hours .. ':' ..
            Minutes[2] .. ':' ..
            Seconds[2] .. " [" ..
            string.format("%02d", FlyNumber) .. ']',
            PaintColorFlag)
        --Log menu
        if FlyNumber ~= 0 then
            xs = 12
            ys = 25
            local pix
            for d = 0, FlyNumber - 1 do
                if d % 8 == 0 then
                    xs = 12
                    if d > 0 then
                        ys = ys + 35
                    end
                else
                    xs = xs + 58
                end
                if d == SeleNumber - 1 then
                    pix = 2
                else
                    pix = 1
                end
                logmenu(xs, ys, pix, string.sub(LogData[d + 1], 13, 17))
            end
            --View detailed data
            if DisplayLogFlag then
                displaylog(40, 85, string.format(SeleNumber) .. "#  " .. string.sub(LogData[SeleNumber], 4, 11),
                    LogData[SeleNumber], SetColorFlag)
            end
        end
    end

    --Write log files
    if WriteEnFlag and FlyNumber < 57 then
        FlyNumber = FlyNumber + 1
        SeleNumber = FlyNumber
        --Write LogInfo
        FileObj = io.open(FilePath, "w")
        LogInfo =
            string.format("%d", getDateTime().year) .. '/' ..
            string.format("%02d", getDateTime().mon) .. '/' ..
            string.format("%02d", getDateTime().day) .. '|' ..
            Hours .. ':' .. Minutes[2] .. ':' .. Seconds[2] .. '|' ..
            string.format("%02d", FlyNumber) .. "\n"
        io.write(FileObj, LogInfo)
        --Write History Log
        for w = 1, FlyNumber - 1 do
            io.write(FileObj, LogData[w])
        end
        --Write New Log [ 01|10:30:54|00:27|0017|001|1859|007.9|0178|23.1|22.5|+020|+019|+031|+031|+100|+080|+103|+079|100|099|075 ]
        LogData[FlyNumber] =
            string.format("%02d", FlyNumber) .. '|' .. --Number
            string.format("%02d", getDateTime().hour) .. ':' ..
            string.format("%02d", getDateTime().min) .. ':' ..
            string.format("%02d", getDateTime().sec) .. '|' ..             --Date time
            Minutes[1] .. ':' .. Seconds[1] .. '|' ..                      --Flight time
            string.format("%04d", ValueMinMax[4][1] - CapaStart) .. '|' .. --Capa used
            string.format("%03d", FuelStart - ValueMinMax[5][1]) .. '|' .. --Fuel used
            string.format("%04d", ValueMinMax[3][2]) .. '|' ..             --HSpd Max
            string.format("%05.1f", ValueMinMax[2][2]) .. '|' ..           --Current Max
            string.format("%04d", PowerMax[1]) .. '|' ..                   --Power Max
            string.format("%04.1f", ValueMinMax[1][2]) .. '|' ..           --Voltage Max
            string.format("%04.1f", ValueMinMax[1][3]) .. '|' ..           --Voltage Min
            string.format("%+04d", ValueMinMax[6][2]) .. '|' ..            --EscT Max
            string.format("%+04d", ValueMinMax[6][3]) .. '|' ..            --EscT Min
            string.format("%+04d", ValueMinMax[7][2]) .. '|' ..            --McuT Max
            string.format("%+04d", ValueMinMax[7][3]) .. "|" ..            --EcuT Min
            string.format("%+04d", ValueMinMax[8][2]) .. '|' ..            --1RSS Max
            string.format("%+04d", ValueMinMax[8][3]) .. '|' ..            --1RSS Min
            string.format("%+04d", ValueMinMax[9][2]) .. '|' ..            --2RSS Max
            string.format("%+04d", ValueMinMax[9][3]) .. '|' ..            --2RSS Min
            string.format("%03d", ValueMinMax[10][2]) .. '|' ..            --RQly Max
            string.format("%03d", ValueMinMax[10][3]) .. '|' ..            --RQly Min
            string.format("%03d", ValueMinMax[11][2]) .. "\n"              --Throttle Max
        io.write(FileObj, LogData[FlyNumber])
        io.close(FileObj)
        --Data writing completed
        WriteEnFlag = false
    end
end

return {
    name = name,
    options = options,
    create = create,
    update = update,
    refresh = refresh,
    background = background
}
