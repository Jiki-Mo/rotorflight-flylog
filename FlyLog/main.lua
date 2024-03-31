--[[
Release:
v0.1 2024-01-19
v0.2 2024-02-07
v0.3 2024-02-13rq
v0.4 2024-02-22 (RF2 20240218 Version)
v0.5 2024-03-21
v0.6 2024-03-31
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
local NAME = "FlyLog"
local VERSION = "v0.6"

--Variable
local crsf_field = { "RxBt", "Curr", "Alt", "Capa", "Bat%", "GSpd", "Sats", "1RSS", "2RSS", "RQly", "Hdg", "FM" }
local fport_field = { "VFAS", "Curr", "RPM1", "5250", "Fuel", "EscT", "Tmp1", "RSSI", "TRSS", "TQly", "Hdg", "FM" }
local display_list = { "Voltage[V]", "Current[A]", "HSpd[rpm]", "FM:" }
local data_format = { "%.1f", "%.1f", "%d", "%s" }
local data_field = {}

--Define
local TELE_ITEMS = 12
local FM_INDEX = 12
local DISP_FM_INDEX = 4
local LOG_INFO_LEN = 22
local LOG_DATA_LEN = 104
--Variable
local model_name = ""
local protocol_type = 0
local value_min_max = {}
local data_hag = { 11, 10 }
local power_max = { 0, 0 }
local capa_start = 0
local fuel_start = 0
local field_id = {}
local time_os = 0
local ring_data = 0
local sync_fuel_value = 0
local wait_count = 0
local pic_obj
local file_name = ""
local file_path = ""
local file_obj
local log_info = ""
local log_data = {}
local fly_number = 0
local sele_number = 0
local second = { 0, 0, 0 }
local total_second = 0
local hours = 0
local minutes = { 0, 0 }
local seconds = { 0, 0 }
local play_speed = 0
--Flag
local paint_color_flag = BLACK
local set_color_flag
local batter_on_flag
local init_sync_flag
local spoolup_flag
local display_log_flag
local write_en_flag
local sliding_flag
local ring_start_flag
local ring_end_flag

local options = {
    { "TelemetryValueColor", COLOR,  BLACK },
    { "ThrottleChannel",     SOURCE, 215 }, --CH6
    { "LowVoltageValue_x10", VALUE,  216,  0, 550 },
    { "LowFuelValue",        VALUE,  0,    0, 100 }
}

--create
local function create(zone, options)
    local widget = {
        zone = zone,
        options = options
    }
    local module = {}
    --Head speed ratio
    --local _, _, major, minor, rev, osname = getVersion()

    --Variable initialization
    sele_number = 1
    for i = 1, #second do
        second[i] = 0
    end
    total_second = 0
    --Flag
    write_en_flag = false
    sliding_flag = false
    ring_start_flag = false
    ring_end_flag = false

    --Model Name
    model_name = model.getInfo().name

    --Initialize the array
    for i = 1, TELE_ITEMS - 1 do
        value_min_max[i] = { 0, 0, 0 }
    end
    for i = 1, TELE_ITEMS do
        field_id[i] = { 0, 0 }
    end

    --Protocol Type
    module[1] = model.getModule(0) --Internal
    module[2] = model.getModule(1) --External
    protocol_type = 0              --CRSF
    for m = 1, 2 do
        if module[m] ~= nil then
            if module[m].Type == 6 and module[m].protocol == 64 then -- MULTIMODULE D16
                protocol_type = 1                                    -- FPORT
                break
            end
        end
    end

    --Redefine fields
    data_field = protocol_type == 1 and fport_field or crsf_field

    --Get ID
    for k, v in pairs(data_field) do
        local field_info = getFieldInfo(v)
        if field_info ~= nil then
            field_id[k][1] = field_info.id
            field_id[k][2] = true
        else
            field_id[k][1] = 0;
            field_id[k][2] = false
        end
    end

    --Loading pic
    pic_obj = Bitmap.open("/WIDGETS/FlyLog/a.png")

    --log
    file_name = '[' .. model_name .. ']' ..
        string.format("%d", getDateTime().year) ..
        string.format("%02d", getDateTime().mon) ..
        string.format("%02d", getDateTime().day) .. ".log"
    file_path = "/WIDGETS/FlyLog/logs/" .. file_name

    local file_info = fstat(file_path)
    local read_count = 1
    if file_info ~= nil then
        if file_info.size > 0 then
            file_obj = io.open(file_path, "r")
            log_info = io.read(file_obj, LOG_INFO_LEN + 1)
            while true do
                log_data[read_count] = io.read(file_obj, LOG_DATA_LEN + 1)
                if #log_data[read_count] == 0 then
                    break
                else
                    read_count = read_count + 1
                end
            end
            io.close(file_obj)
            --Get Total seconds
            hours = string.sub(log_info, 12, 13)
            minutes[2] = string.sub(log_info, 15, 16)
            seconds[2] = string.sub(log_info, 18, 19)
            --Tonumber
            total_second = tonumber(string.sub(log_info, 12, 13)) * 3600
            total_second = total_second + tonumber(string.sub(log_info, 15, 16)) * 60
            total_second = total_second + tonumber(string.sub(log_info, 18, 19))
        end
    else
        file_obj = io.open(file_path, "w")
        log_info =
            string.format("%d", getDateTime().year) .. '/' ..
            string.format("%02d", getDateTime().mon) .. '/' ..
            string.format("%02d", getDateTime().day) .. '|' ..
            "00:00:00" .. '|' ..
            "00\n"
        io.write(file_obj, log_info)
        io.close(file_obj)
    end

    --Parse the data
    local str_temp = string.sub(log_info, 21, 23)
    if tonumber(str_temp) ~= nil then
        fly_number = tonumber(str_temp)
    end
    return widget
end

--update
local function update(widget, options)
    widget.options = options
end

--background
local function background(widget)
end

--fuel_percentage
local function fuel_percentage(xs, ys, capa, number)
    local color = lcd.RGB(255 - number * 2.55, number * 2.55, 0)
    lcd.drawAnnulus(xs, ys, 65, 70, 0, 360, lcd.RGB(100, 100, 100))
    if number ~= 0 then
        lcd.drawAnnulus(xs, ys, 45, 65, (100 - number) * 3.6, 360, color)
    end
    if number ~= 100 then
        lcd.drawAnnulus(xs, ys, 45, 65, 0, (100 - number) * 3.6, lcd.RGB(220, 220, 220))
    end
    lcd.drawText(xs + 2, ys - 10, string.format("%d%%", number), CENTER + VCENTER + DBLSIZE + set_color_flag)
    lcd.drawText(xs, ys + 15, string.format("%dmAh", capa), CENTER + VCENTER + set_color_flag)
end

--get_touch_fly_number
local function get_touch_fly_number(xs, ys, tx, ty, flyn)
    local xst = xs
    local yst = ys
    for k = 0, flyn - 1 do
        if k % 8 == 0 then
            xst = 12
            if k > 0 then
                yst = yst + 35
            end
        else
            xst = xst + 58
        end
        if tx >= xst - 5 and tx <= xst + 48 + 5 and ty >= yst - 5 and ty <= yst + 30 + 5 then
            return k + 1
        end
    end
    return 0
end

--draw_rounded_rectangle
local function draw_rounded_rectangle(xs, ys, w, h, r)
    -- Arc
    lcd.drawArc(xs + r, ys + r, r, 270, 360, paint_color_flag)
    lcd.drawArc(xs + r, ys + h - r, r, 180, 270, paint_color_flag)
    lcd.drawArc(xs + w - r, ys + r, r, 0, 90, paint_color_flag)
    lcd.drawArc(xs + w - r, ys + h - r, r, 90, 180, paint_color_flag)
    -- Line
    lcd.drawLine(xs + r, ys, xs + w - r, ys, SOLID, paint_color_flag)
    lcd.drawLine(xs + r, ys + h, xs + w - r, ys + h, SOLID, paint_color_flag)
    lcd.drawLine(xs, ys + r, xs, ys + h - r, SOLID, paint_color_flag)
    lcd.drawLine(xs + w, ys + r, xs + w, ys + h - r, SOLID, paint_color_flag)
end

--draw_log_menu
local function draw_log_menu(xs, ys, s, str)
    if s then
        lcd.drawBitmap(pic_obj, xs + 1, ys + 1)
    end
    draw_rounded_rectangle(xs, ys, 48 - 1, 30 - 1, 2, paint_color_flag)
    lcd.drawText(xs + 24, ys + 15, str, CENTER + VCENTER + paint_color_flag)
end

--draw_log_content
local function draw_log_content(xs, ys, title, message, flags)
    local extract = {}
    local value
    local index, length = 4, 8
    --Date time
    extract[1] = string.sub(message, index, index + length - 1)
    --Flight time
    index = 13
    length = 5
    extract[2] = string.sub(message, index, index + length - 1)
    --Capa Fuel HSpd Current Power [[Voltage EscT McuT 1RSS 2RSS RQly] MAX MIN] Throttle
    for t = 1, 18 do
        index = index + length + 1
        if t == 2 or t == 16 or t == 17 or t == 18 then
            length = 3
        elseif t == 4 then
            length = 5
        else
            length = 4
        end
        value = tonumber(string.sub(message, index, index + length - 1))
        if t == 4 or t == 6 or t == 7 then
            extract[t + 2] = string.format("%.1f", value)
        else
            extract[t + 2] = string.format("%d", value)
        end
    end
    --Display
    draw_rounded_rectangle(xs, ys, 400 - 1, 155 - 1, 2, paint_color_flag)
    lcd.drawLine(xs, ys + 28, xs + 400 - 2, ys + 28, SOLID, paint_color_flag)
    lcd.drawLine(xs + 200, ys + 28, xs + 200, ys + 155 - 2, SOLID, paint_color_flag)
    lcd.drawText(xs + 5, ys + 5, title, paint_color_flag)
    lcd.drawText(xs + 5, ys + 30,
        "Time: " .. extract[2] .. '\n' ..
        "Capa: " .. extract[3] .. "[mAh]\n" ..
        "Fuel: " .. extract[4] .. "[%]\n" ..
        "HSpd: " .. extract[5] .. "[rpm]-" .. extract[20] .. "[%]\n" ..
        "Current: " .. extract[6] .. "[A]\n" ..
        "Power: " .. extract[7] .. "[W]"
        , flags)
    lcd.drawText(xs + 205, ys + 30,
        "Voltage: " .. extract[8] .. " -> " .. extract[9] .. "[V]\n" ..
        "EscT: " .. extract[11] .. " -> " .. extract[10] .. "[°C]\n" ..
        "McuT: " .. extract[13] .. " -> " .. extract[12] .. "[°C]\n" ..
        data_field[8] .. ": " .. extract[14] .. " -> " .. extract[15] .. "[dB]\n" ..
        data_field[9] .. ": " .. extract[16] .. " -> " .. extract[17] .. "[dB]\n" ..
        data_field[10] .. ": " .. extract[18] .. " -> " .. extract[19] .. "[%]"
        , flags)
end

--refresh
local function refresh(widget, event, touchState)
    local y_offset = 13
    local line_height = 48
    local xs = widget.zone.x --0
    local ys = widget.zone.y --0
    local xe = widget.zone.w --392
    local ye = widget.zone.h --168
    local get_value
    local widget_flag = false
    local touch_key
    local protocol_str

    --Layout Mode
    if xe < 480 and ye < 272 then --Widget 392x168 Full 480x272
        widget_flag = true
        display_log_flag = false
    end

    --Options
    lcd.setColor(CUSTOM_COLOR, widget.options.TelemetryValueColor)
    set_color_flag = lcd.getColor(CUSTOM_COLOR)
    protocol_str = protocol_type == 1 and "[FPORT]" or "[CRSF]"

    --Event
    if event ~= 0 then
        if touchState then
            if event == EVT_TOUCH_FIRST and display_log_flag == false then
                touch_key = get_touch_fly_number(12, 25, touchState.x, touchState.y, fly_number)
                if touch_key ~= 0 then
                    sele_number = touch_key
                    display_log_flag = true
                    playTone(100, 200, 100, PLAY_NOW, 10)
                end
            elseif event == EVT_TOUCH_BREAK and sliding_flag then
                sliding_flag = false
                if display_log_flag then
                    display_log_flag = false
                else
                    lcd.exitFullScreen()
                end
                playTone(10000, 200, 100, PLAY_NOW, -60)
            elseif event == EVT_TOUCH_TAP then
            elseif event == EVT_TOUCH_SLIDE then
                if touchState.swipeRight then
                    sliding_flag = true
                elseif touchState.swipeLeft then
                elseif touchState.swipeUp then
                elseif touchState.swipeDown then
                else
                end
            end
        else
            if event == EVT_VIRTUAL_PREV and display_log_flag == false then
                if sele_number > 1 then
                    sele_number = sele_number - 1
                else
                    sele_number = fly_number
                end
                playTone(200, 50, 100, PLAY_NOW)
            elseif event == EVT_VIRTUAL_NEXT and display_log_flag == false then
                if sele_number < fly_number then
                    sele_number = sele_number + 1
                else
                    sele_number = 1;
                end
                playTone(200, 50, 100, PLAY_NOW)
            elseif event == EVT_VIRTUAL_ENTER then
                if display_log_flag then
                    display_log_flag = false
                else
                    display_log_flag = true
                end
                playTone(100, 200, 100, PLAY_NOW, 10)
            elseif event == EVT_VIRTUAL_EXIT then
            elseif event == EVT_VIRTUAL_PREV_PAGE then
            elseif event == EVT_VIRTUAL_NEXT_PAGE then
            end
        end
    end

    --FM
    if widget_flag then --Widget 392x168
        lcd.drawText(xs, ys, NAME .. ' ' .. VERSION .. ' ' .. protocol_str .. ' ' .. '[' .. model_name .. ']', paint_color_flag)
        lcd.drawText(xs + 261, ys, display_list[DISP_FM_INDEX], paint_color_flag)
        if field_id[FM_INDEX][2] then
            get_value = getValue(field_id[FM_INDEX][1])
            if get_value == 0 then
                lcd.drawText(xs + 261 + 30, ys, "No Tele", BLINK + paint_color_flag)
                ring_data = 0
                wait_count = 0
                sync_fuel_value = 0
                play_speed = 0
                time_os = getTime()
                init_sync_flag = false
                batter_on_flag = false
                spoolup_flag = false
                if ring_end_flag then
                    ring_start_flag = false
                    ring_end_flag = false
                end
            else
                --Hint
                if protocol_type == 1 then --FPORT
                    get_value = bit32.band(get_value, 0x0007)
                    if get_value == 1 then
                        lcd.drawText(xs + 261 + 30, ys, "DISARMED", paint_color_flag)
                    elseif get_value == 5 then
                        lcd.drawText(xs + 261 + 30, ys, "ARMED", paint_color_flag)
                    else
                        lcd.drawText(xs + 261 + 30, ys, "ARMING", paint_color_flag)
                    end
                else --CRSF
                    lcd.drawText(xs + 261 + 30, ys, string.format(data_format[DISP_FM_INDEX], get_value), paint_color_flag)
                end
                --Control
                if get_value == "DISARMED" or get_value == 1 then
                    if batter_on_flag == false then
                        if getTime() - time_os > 350 then
                            time_os = getTime()
                            init_sync_flag = true
                            batter_on_flag = true
                            --Zeros
                            for i = 1, #value_min_max do
                                for j = 1, #value_min_max[i] do
                                    value_min_max[i][j] = 0
                                end
                            end
                            power_max[1] = 0
                            power_max[2] = 0
                        end
                    end
                    if spoolup_flag then
                        spoolup_flag = false
                        write_en_flag = true
                    end
                elseif spoolup_flag == false and (get_value == "OFF" or get_value == "SPOOLUP" or get_value == 5) then
                    second[1] = 0
                    spoolup_flag = true
                    --Synchronize data before starting
                    capa_start = value_min_max[4][1]
                    fuel_start = value_min_max[5][1]
                    power_max[1] = 0
                    power_max[2] = 0
                    for s = 1, TELE_ITEMS - 1 do
                        value_min_max[s][2] = value_min_max[s][1]
                        value_min_max[s][3] = value_min_max[s][1]
                    end
                end
            end
        else
            lcd.drawText(xs + 261 + 30, ys, "No Tele", BLINK + paint_color_flag)
        end
    end

    --Telemetry data
    for k = 1, TELE_ITEMS - 1 do
        if k == 1 then
            xs = 150
            ys = 20
        end
        if k < 4 and widget_flag then
            lcd.drawText(xs, ys, display_list[k], paint_color_flag)
        end
        if field_id[k][2] then
            get_value = getValue(field_id[k][1])
            --CRSF
            if protocol_type == 0 then
                if k == data_hag[1] then
                    get_value = get_value * data_hag[2];
                end
            end
            value_min_max[k][1] = get_value
            if init_sync_flag then
                value_min_max[k][2] = get_value
                value_min_max[k][3] = get_value
                --Ring
                if ring_start_flag == false and value_min_max[5][1] > 0 then
                    sync_fuel_value = sync_fuel_value + 1
                    if sync_fuel_value > 29 then
                        wait_count = 0
                        ring_start_flag = true
                        ring_end_flag = false
                    end
                else
                    sync_fuel_value = 0
                end
            else
                if batter_on_flag and get_value ~= 0 then
                    if get_value > value_min_max[k][2] then
                        value_min_max[k][2] = get_value
                    elseif get_value < value_min_max[k][3] then
                        value_min_max[k][3] = get_value
                    end
                end
            end
            if k < 4 and widget_flag then
                lcd.drawText(xs, ys + y_offset, string.format(data_format[k], value_min_max[k][1]), DBLSIZE + set_color_flag)                                                         --Real time
                lcd.drawText(xs + 85, ys + y_offset, string.format(data_format[k], value_min_max[k][2]), set_color_flag)                                                              --Max
                if k == 2 then
                    lcd.drawText(xs + 85, ys + y_offset + 15, string.format("%dW", power_max[2]), set_color_flag)                                                                     --Power
                elseif k == 3 then
                    if protocol_type == 1 then                                                                                                                                        --FPORT
                        lcd.drawText(xs + 85, ys + y_offset + 15, string.format("%.f%%", (getOutputValue(widget.options.ThrottleChannel - 210) + 1024) / 2048 * 100), set_color_flag) --Throttle [Remote control channel value]
                    else                                                                                                                                                              --CRSF
                        lcd.drawText(xs + 85, ys + y_offset + 15, string.format("%d%%", value_min_max[11][1]), set_color_flag)                                                        --Throttle [FC real-time value]
                    end
                else
                    lcd.drawText(xs + 85, ys + y_offset + 15, string.format(data_format[k], value_min_max[k][3]), set_color_flag) --Voltage Min
                end
            end
        else
            if k < 4 and widget_flag then
                lcd.drawText(xs, ys + y_offset, "----", DBLSIZE + set_color_flag)
            end
        end
        ys = ys + line_height
    end
    --Limit RPM maximum
    value_min_max[3][2] = math.min(value_min_max[3][2], 9999)

    --Power
    power_max[2] = math.min(math.floor(value_min_max[1][1] * value_min_max[2][1]), 9999)
    if power_max[1] < power_max[2] then
        power_max[1] = power_max[2]
    end

    --Synchronize
    if init_sync_flag then
        if getTime() - time_os > 1500 then
            init_sync_flag = false
        end
    end

    --Timer Warning
    if spoolup_flag then
        second[3] = getRtcTime()
        if second[2] ~= second[3] then
            second[2] = second[3]
            --Subtotal
            second[1] = second[1] + 1
            --Total
            total_second = total_second + 1
            --Warning
            if widget.options.LowVoltageValue_x10 ~= 0 or widget.options.LowFuelValue ~= 0 then
                if value_min_max[1][1] < widget.options.LowVoltageValue_x10 / 10 or value_min_max[5][1] < widget.options.LowFuelValue then
                    play_speed = play_speed + 1
                    if play_speed > 2 then
                        play_speed = 0
                        playFile("/WIDGETS/FlyLog/batlow.wav")
                        playHaptic(25, 50, 0)
                        playHaptic(10, 20, 1)
                    end
                else
                    play_speed = 0
                end
            end
        end
    end

    --Format Timer
    minutes[1] = string.format("%02d", math.floor(second[1] % 3600 / 60))
    seconds[1] = string.format("%02d", second[1] % 3600 % 60)
    hours = string.format("%02d", math.floor(total_second / 3600))
    minutes[2] = string.format("%02d", math.floor(total_second % 3600 / 60))
    seconds[2] = string.format("%02d", total_second % 3600 % 60)

    --Display mode
    if widget_flag then --Widget 392x168
        xs = widget.zone.x
        ys = widget.zone.y
        --Dividing line
        lcd.drawLine(xs + 145, ys + 66, xe, ys + 66, SOLID, paint_color_flag)
        lcd.drawLine(xs + 145, ys + 66 + line_height, xe, ys + 66 + line_height, SOLID, paint_color_flag)
        lcd.drawLine(xs + 285, ys + 20, xs + 285, ye - 6, SOLID, paint_color_flag)

        --Fuel Percentage
        if ring_start_flag and ring_end_flag == false then
            if ring_data >= value_min_max[5][1] then
                wait_count = wait_count + 1
                if wait_count > 99 then
                    ring_end_flag = true
                end
            else
                ring_data = ring_data + 1
                wait_count = 0
            end
        else
            if ring_end_flag then
                ring_data = value_min_max[5][1]
            else
                ring_data = 0
            end
        end
        fuel_percentage(xs + 70, ys + 90, value_min_max[4][1], ring_data)

        --Timer 48x112
        xs = 280
        ys = 20
        --T1
        lcd.drawText(xs + 12, ys, "T1", paint_color_flag)
        lcd.drawText(xs + 45, ys, "M", paint_color_flag)
        lcd.drawText(xs + 45 + 53, ys, "S", paint_color_flag)
        lcd.drawText(xs + 12, ys + y_offset, minutes[1], DBLSIZE + set_color_flag)
        lcd.drawText(xs + 65, ys + y_offset, seconds[1], DBLSIZE + set_color_flag)
        --T2
        ys = ys + line_height
        lcd.drawText(xs + 12, ys, "T2", paint_color_flag)
        if total_second >= 3600 then
            lcd.drawText(xs + 45, ys, "H", paint_color_flag)
            lcd.drawText(xs + 45 + 53, ys, "M", paint_color_flag)
            lcd.drawText(xs + 12, ys + y_offset, hours, DBLSIZE + set_color_flag)
            lcd.drawText(xs + 65, ys + y_offset, minutes[2], DBLSIZE + set_color_flag)
        else
            lcd.drawText(xs + 45, ys, "M", paint_color_flag)
            lcd.drawText(xs + 45 + 53, ys, "S", paint_color_flag)
            lcd.drawText(xs + 12, ys + y_offset, minutes[2], DBLSIZE + set_color_flag)
            lcd.drawText(xs + 65, ys + y_offset, seconds[2], DBLSIZE + set_color_flag)
        end
        --Number of flights
        ys = ys + line_height - 18
        lcd.drawText(xs + 20, ys, string.format("%02d", fly_number), XXLSIZE + set_color_flag)
        lcd.drawText(xs + 45 + 53, ys + 18, "N", paint_color_flag)
    else --Full 480x272
        --Title
        lcd.drawText(12, 2,
            file_name .. "  " ..
            hours .. ':' ..
            minutes[2] .. ':' ..
            seconds[2] .. " [" ..
            string.format("%02d", fly_number) .. ']', paint_color_flag)
        --Menu
        if fly_number ~= 0 then
            xs = 12
            ys = 25
            --View the log contents
            if display_log_flag then
                draw_log_content(40, 58, string.format(sele_number) .. "#  " .. string.sub(log_data[sele_number], 4, 11), log_data[sele_number], set_color_flag)
            else
                --Log menu
                for m = 0, fly_number - 1 do
                    if m % 8 == 0 then
                        xs = 12
                        if m > 0 then
                            ys = ys + 35
                        end
                    else
                        xs = xs + 58
                    end
                    draw_log_menu(xs, ys, m == sele_number - 1, string.sub(log_data[m + 1], 13, 17))
                end
            end
        end
    end

    --Write log files
    if write_en_flag and fly_number < 57 then
        fly_number = fly_number + 1
        sele_number = fly_number
        --Write log_info
        file_obj = io.open(file_path, "w")
        log_info =
            string.format("%d", getDateTime().year) .. '/' ..
            string.format("%02d", getDateTime().mon) .. '/' ..
            string.format("%02d", getDateTime().day) .. '|' ..
            hours .. ':' .. minutes[2] .. ':' .. seconds[2] .. '|' ..
            string.format("%02d", fly_number) .. "\n"
        io.write(file_obj, log_info)
        --Write History Log
        for w = 1, fly_number - 1 do
            io.write(file_obj, log_data[w])
        end
        --Write New Log [ 10|16:20:36|04:46|4533|087|2289|159.9|3293|24.9|20.2|+099|+033|+045|+043|-032|-072|-030|-084|100|096|100 ]
        log_data[fly_number] =
            string.format("%02d", fly_number) .. '|' .. --Number
            string.format("%02d", getDateTime().hour) .. ':' ..
            string.format("%02d", getDateTime().min) .. ':' ..
            string.format("%02d", getDateTime().sec) .. '|' ..                --Date time
            minutes[1] .. ':' .. seconds[1] .. '|' ..                         --Flight time
            string.format("%04d", value_min_max[4][1] - capa_start) .. '|' .. --Capa used
            string.format("%03d", fuel_start - value_min_max[5][1]) .. '|' .. --Fuel used
            string.format("%04d", value_min_max[3][2]) .. '|' ..              --HSpd Max
            string.format("%05.1f", value_min_max[2][2]) .. '|' ..            --Current Max
            string.format("%04d", power_max[1]) .. '|' ..                     --Power Max
            string.format("%04.1f", value_min_max[1][2]) .. '|' ..            --Voltage Max
            string.format("%04.1f", value_min_max[1][3]) .. '|' ..            --Voltage Min
            string.format("%+04d", value_min_max[6][2]) .. '|' ..             --EscT Max
            string.format("%+04d", value_min_max[6][3]) .. '|' ..             --EscT Min
            string.format("%+04d", value_min_max[7][2]) .. '|' ..             --McuT Max
            string.format("%+04d", value_min_max[7][3]) .. "|" ..             --EcuT Min
            string.format("%+04d", value_min_max[8][2]) .. '|' ..             --1RSS Max
            string.format("%+04d", value_min_max[8][3]) .. '|' ..             --1RSS Min
            string.format("%+04d", value_min_max[9][2]) .. '|' ..             --2RSS Max
            string.format("%+04d", value_min_max[9][3]) .. '|' ..             --2RSS Min
            string.format("%03d", value_min_max[10][2]) .. '|' ..             --RQly Max
            string.format("%03d", value_min_max[10][3]) .. '|' ..             --RQly Min
            string.format("%03d", value_min_max[11][2]) .. "\n"               --Throttle Max
        io.write(file_obj, log_data[fly_number])
        io.close(file_obj)
        --Data writing completed
        write_en_flag = false
    end
end

--api
return {
    name = NAME,
    options = options,
    create = create,
    update = update,
    refresh = refresh,
    background = background
}
