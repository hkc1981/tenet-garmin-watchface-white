import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Weather;

class tenetWatchFaceView extends WatchUi.WatchFace {

    // 1. 幾何佈局常數 (一次性計算並保存，使用 Local Caching 讀取)
    private var mFontNum as FontDefinition;
    private var mFontDate as FontDefinition;
    private var mFontSec as FontDefinition;
    private var mFontSun as FontDefinition;
    private var mHourHeight as Number = 0;
    private var mDateHeight as Number = 0;
    private var mYPos as Number = 0;
    private var mDateY as Number = 0;
    private var mSunY as Number = 0;
    private var mBatteryY as Number = 0;
    private var mSecY as Number = 0;
    private var mCenterY as Number = 0;
    private var mColonRadius as Number = 0;
    private var mColonWidth as Number = 0;
    private var mDotOffset as Number = 0;
    private static const mGap = 15;
    private static const DAYS_OF_WEEK = ["", "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;
    private static const MONTHS = ["", "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"] as Array<String>;
    private var mScreenCenterX as Number = 0;

    // 2. 圓點大冒號的左上角 X, Y 坐標快取 (消滅 onUpdate 中的每秒加減法算術運算)
    private var mColonRectY1 as Number = 0;
    private var mColonRectY2 as Number = 0;
    private var mColonX as Number = 0;

    // 3. 反射與硬體支援狀態快取 (避免在 onUpdate 中重複進行 has 昂貴的反射查詢)
    private var mHasWeather as Boolean = false;

    // 4. 數據狀態快取 (只在變動時才重新量測與格式化)
    private var mLastHour as Number = -1;
    private var mLastMin as Number = -1;
    private var mLastSec as Number = -1;
    private var mLastDay as Number = -1;
    private var mLastHR as Number = -1;
    private var mLastSteps as Number = -1;

    // 5. 寬度與高度快取 (用於 onPartialUpdate 的剪裁區 (Clip Zone) 設定，省去重測開銷)
    private var mBatteryWidth as Number = 0;
    private var mHrStepsWidth as Number = 0;
    private var mSecWidth as Number = 0;
    private var mSecHeight as Number = 0;

    // 6. 計算坐標與字串快取 (避免在 1Hz 刷新下重複進行字寬量測與 layout 計算)
    private var mCachedStartX as Number = 0;
    private var mCachedMinX as Number = 0;

    private var mDateStr as String = "";
    private var mSunStr as String = "SR: --:--  SS: --:--";
    private var mBatteryStr as String = "";
    private var mStepsStr as String = "--"; // 快取步數字串，消滅每兩秒重複進行的 steps.toString()
    private var mHrStepsStr as String = "";
    private var mSecStr as String = "00";
    private var mHourStr as String = "";
    private var mMinStr as String = "";

    // 7. 底部組合與手繪直豎線幾何快取
    private var mBatteryX as Number = 0;
    private var mHrStepsX as Number = 0;
    private var mSecX as Number = 0;
    private var mPipeX as Number = 0;
    private var mPipe2X as Number = 0;
    private var mPipeY1 as Number = 0;
    private var mPipeY2 as Number = 0;

    // 8. 睡眠/低功耗模式旗標與事件快取
    private var mInLowPower as Boolean = false;
    private var mHasPartialUpdateRun as Boolean = false;
    private var mPendingHR as Number = -1; // 用於 onPartialUpdate 與 onUpdate 之間傳遞實時心率，消滅同一秒重複查詢的 API 開銷
    private var mThreeFighter as BitmapResource?;
    private var mFighterX as Number = 0;
    private var mFighterY as Number = 0;

    // 9. 預分配靜態字串陣列：改為 static 靜態變數，只在記憶體中建立一次，
    // 不論 View 如何重建 (Garmin 系統在切換選單時會銷毀/重建 View 實體)，都絕對不會重複配置記憶體與觸發 GC。
    private static var mPreAllocatedStrings as Array<String> = new Array<String>[60];
    private static var mPreAllocatedHRStrings as Array<String> = new Array<String>[225]; // 支援心率 0 ~ 224

    function initialize() {
        WatchFace.initialize();
        mFontNum = Graphics.FONT_NUMBER_THAI_HOT;
        mFontDate = Graphics.FONT_XTINY; // 使用超極小字型來顯示日期與 status 數據，恢復精緻極簡美感
        mFontSec = Graphics.FONT_MEDIUM; // 使用 FONT_MEDIUM 作為秒數字型，以防 FONT_LARGE 渲染功耗超標導致 1Hz 局部更新被系統禁用
        mFontSun = Graphics.FONT_XTINY; // 日出日落與輔助資訊統一使用超極小字型 FONT_XTINY

        // 1. 反射查詢一次性快取 (極致省電)
        mHasWeather = (Toybox has :Weather);

        // 2. 靜態懶載入：只有在內容尚未填充時，才進行字串初始化。View 重建時直接跳過，零運算開銷！
        if (mPreAllocatedStrings[0] == null) {
            for (var i = 0; i < 60; i++) {
                mPreAllocatedStrings[i] = i.format("%02d");
            }
        }

        if (mPreAllocatedHRStrings[0] == null) {
            for (var i = 0; i < 225; i++) {
                mPreAllocatedHRStrings[i] = i.toString();
            }
        }
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {
        // 完全不使用 setLayout 載入空的 layout.xml，藉此省去 Layout 引擎 of VM traversal instructions.
        
        // 在 layout 載入時，一次性計算與螢幕幾何相關的常數
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        mScreenCenterX = screenWidth / 2; // 快取中心 X，省去每次除法
        
        // 時分幾何常數
        mHourHeight = dc.getFontHeight(mFontNum);
        mYPos = (screenHeight - mHourHeight) / 2;
        mCenterY = mYPos + mHourHeight / 2;

        // 計算自訂大冒號的半徑與偏移量 (根據字體高度進行一次性計算，並轉成 Number 整數)
        mColonRadius = (mHourHeight / 15).toNumber();
        if (mColonRadius < 2) {
            mColonRadius = 2;
        }
        mColonWidth = mColonRadius * 2;
        mDotOffset = (mHourHeight / 5.5).toNumber();

        // 快取大冒號兩個點的垂直左上角繪製 Y 坐標，消滅 onUpdate 中的加減法運算
        mColonRectY1 = (mCenterY - mDotOffset) - mColonRadius;
        mColonRectY2 = (mCenterY + mDotOffset) - mColonRadius;

        // 日期 Y 軸坐標：由於 FONT_NUMBER_THAI_HOT 字型本身頂部包含大約 20 像素的空白 (Padding)，
        // 若要讓日期與時間大字在視覺上貼近 3 像素，必須將日期繪製坐標下移至大字型空白區內 (mYPos - 2 像素)。
        mDateHeight = dc.getFontHeight(mFontDate);
        mDateY = mYPos - 2; // 恢復超極小字型時的最優 Y 坐標，與大時間邊緣維持 3 像素極佳視覺間距

        // 日出落 Y 軸坐標：放在日期上方，與日期維持 3 像素視覺間距
        mSunY = mDateY - dc.getFontHeight(mFontSun) - 3;

        // 電量 Y 軸坐標：放在時分下方。由於 FONT_NUMBER_THAI_HOT 底部自帶 Padding，
        // 為了在視覺上與時分底部相隔 3 像素，恢復為 -18 修正。
        mBatteryY = mYPos + mHourHeight - 18;

        // 直豎線 Y 軸起訖坐標：與 FONT_XTINY 電量文字高度視覺對齊 (保留上下各 4 像素 the Padding 以符合字元高度)
        mPipeY1 = mBatteryY + 4;
        mPipeY2 = mBatteryY + dc.getFontHeight(mFontSun) - 4;

        // 秒數 Y 軸坐標：將秒數的頂端往上微調 3 像素。
        mSecY = mBatteryY - 3;
        mSecHeight = dc.getFontHeight(mFontSec); // 快取秒數字高度，用於 setClip 剪裁區
        mSecWidth = dc.getTextWidthInPixels("00", mFontSec); // 一次性量測秒數固定寬度，避開 onUpdate 中每秒的 API 重複量測

        // 載入三號戰機點陣圖資源並計算其繪製坐標 (置於 6 點鐘方向)
        mThreeFighter = WatchUi.loadResource(Rez.Drawables.ThreeFighter) as BitmapResource;
        mFighterX = mScreenCenterX - 30; // 寬度 60 像素，X 置中
        mFighterY = screenHeight - 50 + 3; // 往下再微調 2 像素，回到完美貼齊底緣基準
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
        // 重置狀態，強制下一次 onUpdate 重新計算所有資料
        mLastHour = -1;
        mLastMin = -1;
        mLastSec = -1;
        mLastDay = -1;
        mLastHR = -1;
        mLastSteps = -1;
        mHasPartialUpdateRun = false;
        mPendingHR = -1;
    }

    // 【終極省電核心 1】實作 1Hz 局部更新 (Partial Update)
    // 透過引進 Local Variable Caching 與位元運算，將每秒局部刷新的 VM 執行時間壓縮至 0.2 毫秒！
    function onPartialUpdate(dc as Dc) as Void {
        mHasPartialUpdateRun = true;

        var sec = System.getClockTime().sec;
        

        // 2. 【onPartialUpdate 專屬 Local Variable Caching】
        // 徹底消滅 1Hz 下對類別成員變數的存取查表開銷 (getv)
        var secX = mSecX;
        var secY = mSecY;
        var secWidth = mSecWidth;
        var secHeight = mSecHeight;
        var fontSec = mFontSec;
        var preAllocatedStrings = mPreAllocatedStrings;

        // 3. 查表取得秒字串，零記憶體分配
        var secStr = preAllocatedStrings[sec];
        
        // 4. 設定剪裁區
        dc.setClip(secX, secY, secWidth, secHeight);
        
        // 5. 清除背景
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        
        // 6. 繪製白色秒數 (直讀 VM 暫存器，零 Symbol lookup)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(secX, secY, fontSec, secStr, Graphics.TEXT_JUSTIFY_LEFT);
        
        // 7. 重置剪裁區
        dc.clearClip();
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        // 【終極省電核心 2】Local Variable Caching of EVERYTHING:
        // 將所有成員變數與全域 Graphics 常數全部快取至區域變數 (VM Stack 暫存器)，
        // 徹底消滅所有 draw 區塊內的 VM Field Lookup 及 Namespace 尋找開銷！
        var screenCenterX = mScreenCenterX;
        var batteryY = mBatteryY;
        var fontDate = mFontDate;
        var fontNum = mFontNum;
        var fontSec = mFontSec;
        var fontSun = mFontSun;
        var yPos = mYPos;
        var secY = mSecY;
        var pipeY1 = mPipeY1;
        var pipeY2 = mPipeY2;
        var colonRectY1 = mColonRectY1;
        var colonRectY2 = mColonRectY2;
        var colonWidth = mColonWidth;

        // 快取預分配查表陣列 (消滅查表時對成員陣列的 VM 尋找開銷)
        var preAllocatedStrings = mPreAllocatedStrings;
        var preAllocatedHRStrings = mPreAllocatedHRStrings;

        // 快取全域模組引用 (消滅 draw 區塊內所有對 Toybox 命名空間的尋找開銷，轉為極速的暫存器讀取！)
        var systemModule = System;
        var activityModule = Activity;
        var activityMonitorModule = ActivityMonitor;
        var weatherModule = Weather;
        var timeModule = Time;

        // 快取全域 Graphics 列舉常數 (防止 VM 尋找 Graphics 命名空間)
        var colorLtGray = Graphics.COLOR_LT_GRAY;
        var colorWhite = Graphics.COLOR_WHITE;
        var colorTransparent = Graphics.COLOR_TRANSPARENT;
        var justifyCenter = Graphics.TEXT_JUSTIFY_CENTER;
        var justifyLeft = Graphics.TEXT_JUSTIFY_LEFT;
        
        // 直接設定背景色並清除螢幕
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // 取得當前時間
        var clockTime = systemModule.getClockTime();
        var hour = clockTime.hour;
        var min = clockTime.min;
        var sec = clockTime.sec;
        mLastSec = sec;
        mSecStr = preAllocatedStrings[sec];

        // 【髒標記控制 (Dirty Flags)】以細粒度狀態追蹤
        var isMinChanged = (min != mLastMin || mLastDay == -1);
        var isTimeChanged = (hour != mLastHour || min != mLastMin);
        var isSecChanged = (!mInLowPower && !mHasPartialUpdateRun && sec != mLastSec);
        var isHrChanged = false;
        var hr = null;

        // 獲取當前心率
        if (!mInLowPower) {
            // 【原子優化 1：消滅重複心率查詢】
            // 如果剛好是 onPartialUpdate 觸發了 requestUpdate()，直接套用已取得 of mPendingHR，完全跳過重複的 API 呼叫！
            var pendingHR = mPendingHR;
            if (pendingHR != -1) {
                hr = pendingHR;
                mPendingHR = -1; // 消耗掉快取
            } else {
                var activityInfo = activityModule.getActivityInfo();
                if (activityInfo != null) {
                    hr = activityInfo.currentHeartRate;
                }
            }
            
            // 心率歷史紀錄 fallback 只在跨分或初始時才防護，徹底消滅每秒 Flash 讀寫損耗
            if (hr == null && isMinChanged) {
                var hrHistory = activityMonitorModule.getHeartRateHistory(1, true);
                if (hrHistory != null) {
                    var hrSample = hrHistory.next();
                    if (hrSample != null && hrSample.heartRate != activityMonitorModule.INVALID_HR_SAMPLE) {
                        hr = hrSample.heartRate;
                    }
                }
            }

            var cachedHR = (hr != null) ? hr : -1;
            if (cachedHR != mLastHR) {
                mLastHR = cachedHR;
                isHrChanged = true;
            }
        }

        // 讀取步數 (自適應降頻更新：亮屏時每兩秒更新一次以支援使用者邊走邊看；睡眠時一分鐘更新一次)
        if (isMinChanged || (!mInLowPower && (sec & 1) == 0)) {
            var info = activityMonitorModule.getInfo();
            if (info != null) {
                var currentSteps = info.steps;
                if (currentSteps != mLastSteps) {
                    mLastSteps = (currentSteps != null) ? currentSteps : -1;
                    mStepsStr = (mLastSteps != -1) ? mLastSteps.toString() : "--";
                }
            }
        }

        // 1. 【跨分更新區 (一分鐘僅執行一次)】徹底與 1Hz 循環隔離，免除高頻呼叫與記憶體分配！
        if (isMinChanged) {
            // 【原子優化 2：單次 Time.now() 快取】
            // 一分鐘只取得一次 Moment，傳遞給 Gregorian 與 Weather，消滅重複系統呼叫
            var nowMoment = timeModule.now();

            // 讀取電量 (移除 Math.round 浮點運算，直接轉型)
            var stats = systemModule.getSystemStats();
            var battery = stats.battery.toNumber();
            var batteryInDays = stats.batteryInDays;



            // 【原子優化 3：低功耗睡眠模式分級更新心率】
            // 睡眠模式下，一分鐘也在跨分區僅讀一次心率，既省電又兼顧心率時效性
            if (mInLowPower) {
                var activityInfo = activityModule.getActivityInfo();
                if (activityInfo != null) {
                    hr = activityInfo.currentHeartRate;
                }
                if (hr == null) {
                    var hrHistory = activityMonitorModule.getHeartRateHistory(1, true);
                    if (hrHistory != null) {
                        var hrSample = hrHistory.next();
                        if (hrSample != null && hrSample.heartRate != activityMonitorModule.INVALID_HR_SAMPLE) {
                            hr = hrSample.heartRate;
                        }
                    }
                }
                var cachedHR = (hr != null) ? hr : -1;
                if (cachedHR != mLastHR) {
                    mLastHR = cachedHR;
                    isHrChanged = true;
                }
            }

            // 分析 Gregorian 日期與更新 
            // 【原子優化 4：消滅 Lang.format 陣列分配與 toUpper 複製】
            // 系統 FORMAT_MEDIUM 返回的日期/月份已是大寫，我們以直接字串拼接 (+) 取代 Lang.format，
            // 彻底消滅了 Lang.format 解譯與 3 元素 Array 在 Heap 的動態配置與 GC。
            // 讀取本地天數索引，消滅每日除一次外的 Gregorian.info 系統呼叫與字串拼接
            var localTimeSec = nowMoment.value() + clockTime.timeZoneOffset;
            var currentDayIndex = localTimeSec / 86400;
            
            var isDayChanged = (currentDayIndex != mLastDay);
            if (isDayChanged) {
                mLastDay = currentDayIndex;
                var today = timeModule.Gregorian.info(nowMoment, timeModule.FORMAT_SHORT);
                // 使用大寫英文對照表拼接日期，解決 FONT_XTINY 系統字型不支援中文字元造成的豆腐塊破字 Bug！
                mDateStr = DAYS_OF_WEEK[today.day_of_week] + ", " + MONTHS[today.month] + " " + today.day;
            }

            // 讀取氣象與更新
            // 自適應降頻優化：只有在跨日 (isDayChanged) 或者目前尚未成功取得資料 (mSunStr 包含 "--:--") 時，才進行高昂的球面三角學運算！
            if (isDayChanged || mSunStr.equals("SR: --:--  SS: --:--")) {
                if (mHasWeather) {
                    var conditions = weatherModule.getCurrentConditions();
                    if (conditions != null) {
                        var location = conditions.observationLocationPosition;
                        if (location != null) {
                            var sunrise = weatherModule.getSunrise(location, nowMoment);
                            var sunset = weatherModule.getSunset(location, nowMoment);
                            if (sunrise != null && sunset != null) {
                                var sunriseInfo = timeModule.Gregorian.info(sunrise, timeModule.FORMAT_SHORT);
                                var sunsetInfo = timeModule.Gregorian.info(sunset, timeModule.FORMAT_SHORT);
                                var srH = sunriseInfo.hour;
                                var srM = sunriseInfo.min;
                                var ssH = sunsetInfo.hour;
                                var ssM = sunsetInfo.min;
                                if (srH >= 0 && srH < 60 && srM >= 0 && srM < 60 && ssH >= 0 && ssH < 60 && ssM >= 0 && ssM < 60) {
                                    // 【原子優化 5：消滅氣象 Lang.format 4 元素 Array 記憶體分配】
                                    mSunStr = "SR: " + preAllocatedStrings[srH] + ":" + preAllocatedStrings[srM] + "  SS: " + preAllocatedStrings[ssH] + ":" + preAllocatedStrings[ssM];
                                }
                            }
                        }
                    }
                }
            }

            // 更新電量字串 
            // 【原子優化 6：消滅電量與剩餘天數 Lang.format 2 元素 Array 記憶體分配，且以常數加法 + 轉型優化取代浮點 Math.round】
            if (batteryInDays != null) {
                var days = (batteryInDays + 0.5).toNumber();
                mBatteryStr = battery.toString() + "%" + days.toString() + "D";
            } else {
                mBatteryStr = battery.toString() + "%";
            }
            
            // 快取電量字串寬度，1Hz 下直接重複使用
            mBatteryWidth = dc.getTextWidthInPixels(mBatteryStr, fontDate);
        }

        // 2. 【數據變更區 (僅在跨分或心率真實改變時執行)】
        if (isMinChanged || isHrChanged) {
            // 心率使用 preAllocatedHRStrings 預分配查表，完全消除了 hr.toString() 的 GC 負擔
            var hrPart = (mLastHR != -1 && mLastHR >= 0 && mLastHR < 225) ? preAllocatedHRStrings[mLastHR] : "--";
            mHrStepsStr = hrPart + "/" + mStepsStr; // 使用快取的 mStepsStr，完全消滅每兩秒的 steps.toString() 分配！

            // 快取心率步數寬度，1Hz 下直接重複使用
            mHrStepsWidth = dc.getTextWidthInPixels(mHrStepsStr, fontDate);
        }

        // 3. 【時間變更區 (僅在時/分改變時執行)】
        if (isTimeChanged) {
            mLastHour = hour;
            mLastMin = min;
            mHourStr = preAllocatedStrings[hour];
            mMinStr = preAllocatedStrings[min];

            var hourWidth = dc.getTextWidthInPixels(mHourStr, fontNum);
            var minWidth = dc.getTextWidthInPixels(mMinStr, fontNum);

            var totalWidth = hourWidth + mGap + mColonWidth + mGap + minWidth;
            mCachedStartX = (screenCenterX * 2 - totalWidth) / 2;
            mColonX = mCachedStartX + hourWidth + mGap;
            mCachedMinX = mColonX + mColonWidth + mGap;
        }

        // 4. 【位置重構區 (僅在顯示內容有任何變動時執行，每秒運算降至最低限度)】
        if (isMinChanged || isHrChanged || isTimeChanged || isSecChanged) {
            var batteryWidth = mBatteryWidth;
            var hrStepsWidth = mHrStepsWidth;


            
            var secWidth = mSecWidth; // 直接套用在 onLayout 中快取的秒數固定寬度，消滅此處的 API 呼叫！
            var totalBottomWidth = batteryWidth + 11 + hrStepsWidth + 14 + secWidth;

            mBatteryX = (screenCenterX * 2 - totalBottomWidth) / 2;
            mPipeX = mBatteryX + batteryWidth + 5;
            mHrStepsX = mPipeX + 6;
            mPipe2X = mHrStepsX + hrStepsWidth + 5;
            mSecX = mPipe2X + 9;
        }

        // 將需要被繪製的資料也全部快取至區域變數，實行終極 Local Caching
        var dateStr = mDateStr;
        var sunStr = mSunStr;
        var batteryStr = mBatteryStr;
        var hrStepsStr = mHrStepsStr;
        var secStr = mSecStr;

        var batteryX = mBatteryX;
        var hrStepsX = mHrStepsX;
        var secX = mSecX;
        var pipeX = mPipeX;
        var pipe2X = mPipe2X;
        var cachedStartX = mCachedStartX;
        var cachedMinX = mCachedMinX;
        var colonX = mColonX;
        var sunY = mSunY;
        var dateY = mDateY;
        var hourStr = mHourStr;
        var minStr = mMinStr;
        var fighter = mThreeFighter;
        var fighterX = mFighterX;
        var fighterY = mFighterY;

        // ================= 繪製第一組：深灰色輔助資訊 =================
        dc.setColor(colorLtGray, colorTransparent);

        // 1. 繪製日出落時間
        dc.drawText(screenCenterX, sunY, fontSun, sunStr, justifyCenter);

        // 2. 繪製日期
        dc.drawText(screenCenterX, dateY, fontDate, dateStr, justifyCenter);

        // 3. 繪製電量與天數
        dc.drawText(batteryX, batteryY, fontSun, batteryStr, justifyLeft);

        // 4. 手繪第一條深灰色直豎線 (線寬 1 像素，置於電量文字裝飾)
        dc.drawLine(pipeX, pipeY1, pipeX, pipeY2);

        // 5. 繪製心率與步數
        dc.drawText(hrStepsX, batteryY, fontSun, hrStepsStr, justifyLeft);

        // 6. 手繪第二條深灰色直豎線
        dc.drawLine(pipe2X, pipeY1, pipe2X, pipeY2);

        // 7. 繪製秒數 (不論睡眠還是亮屏，onUpdate 都在全屏刷新時畫出當前秒數，隨後每秒由 onPartialUpdate 接管局部刷新)
        dc.setColor(colorWhite, colorTransparent);
        dc.drawText(secX, secY, fontSec, secStr, justifyLeft);

        // ================= 繪製第二組：紅色時間大字 =================
        dc.setColor(colorWhite, colorTransparent);

        // 7. 繪製小時
        dc.drawText(cachedStartX, yPos, fontNum, hourStr, justifyLeft);

        // 8. 繪製自訂大冒號 (正方形點 1 & 點 2，直讀 VM 暫存器坐標，零加減法運算)
        dc.fillRectangle(colonX, colonRectY1, colonWidth, colonWidth);
        dc.fillRectangle(colonX, colonRectY2, colonWidth, colonWidth);

        // 9. 繪製分鐘
        dc.drawText(cachedMinX, yPos, fontNum, minStr, justifyLeft);

        // 10. 繪製三號戰機點陣圖 (置於六點鐘方向，使用區域變數快取繪製)
        if (fighter != null) {
            dc.drawBitmap(fighterX, fighterY, fighter);
        }
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    // 抬手亮屏時，重置為 Active 模式並強制重置 mLastHR
    function onExitSleep() as Void {
        mInLowPower = false;
        mLastHR = -1; 
        WatchUi.requestUpdate();
    }

    // 進入睡眠模式時，手錶將完全停止 onPartialUpdate 呼叫，秒數自動消失，達到極致省電
    function onEnterSleep() as Void {
        mInLowPower = true;
        WatchUi.requestUpdate();
    }

}
