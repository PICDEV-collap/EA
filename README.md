# EA Development

## NY Open Scalper — Opening Range Break & Retest (MQL5)

Expert Advisor สำหรับ MetaTrader 5 ที่เทรดตามระบบ Scalping ตอนตลาดนิวยอร์กเปิด
(20:30 น. ตามเวลาไทย = 9:30 น. New York) อ้างอิงจากระบบของช่อง JDU Trader

- ไฟล์ EA: [`Experts/NYOpenScalper.mq5`](Experts/NYOpenScalper.mq5)

### หลักการของระบบ

1. **Opening Range** — เมื่อแท่งเทียน **M5 แท่งแรก** หลังตลาด NY เปิดจบลง
   EA จะมาร์คเส้น High / Low ของแท่งนั้นเป็นกรอบราคา (วาดเส้นบนกราฟให้ด้วย)
2. **Breakout** — รอแท่งเทียน **M1 ปิด (close) นอกกรอบ** เท่านั้น
   ("ทะลุด้วยเนื้อเทียน" — แค่ไส้เทียนเหลื่อมไม่นับ) และทิศของแท่งต้องตรงกับฝั่งที่ทะลุ
3. **Retest** — รอราคาย้อนกลับมาแตะโซนเส้นที่เพิ่งทะลุ (มี buffer ปรับได้)
4. **แท่งคอนเฟิร์ม** — ห้ามเข้าทันทีที่ชนเส้น ต้องรอแท่ง M1 ทิศทางเดิม
   ที่มี **เนื้อเทียนใหญ่ชัดเจน** (body ≥ `MinBodyPoints` และ body/range ≥ `MinBodyRatio`)
   และปิดออกนอกเส้นอีกครั้ง
5. **Entry** — เปิด market order ทันทีเมื่อแท่งคอนเฟิร์มปิด
   - **SL**: ใต้ Low ของแท่งคอนเฟิร์ม (Buy) / เหนือ High (Sell) + buffer
   - **TP**: ระยะ SL × `RiskRewardRatio` (ค่าเริ่มต้น 1:2)

#### No-Trade Zone (กฎความปลอดภัยตามระบบ)

- ราคายังอยู่ในกรอบ → ไม่เปิดออเดอร์เด็ดขาด
- รีเทสแล้วแต่ **ไม่มีแท่งคอนเฟิร์ม** → ไม่เข้า (รอจนกว่าจะมี หรือหมดเวลา)
- ถ้าราคาปิดทะลุกลับไปอีกฝั่งของกรอบ → ยกเลิก setup เดิม
  (และแท่งนั้นอาจนับเป็น breakout ฝั่งตรงข้ามแทน)
- จำกัดจำนวนไม้ต่อวัน (`MaxTradesPerDay` ค่าเริ่มต้น 1 ไม้/วัน)
- หยุดหา setup หลังเปิดตลาดเกิน `WindowMinutes` นาที (ค่าเริ่มต้น 60 นาที)

### การติดตั้ง

1. เปิด MetaTrader 5 → `File > Open Data Folder`
2. คัดลอก `Experts/NYOpenScalper.mq5` ไปไว้ที่ `MQL5/Experts/`
3. เปิด MetaEditor กด **Compile** (F7)
4. ลาก EA ไปวางบนกราฟคู่เงินที่ต้องการ (แนะนำเปิดกราฟ **M1**)
5. เปิด Algo Trading และตั้งค่า input ให้ถูกต้อง (สำคัญที่สุดคือเวลา — ดูหัวข้อถัดไป)

### คำเตือนสำคัญ: ตั้งเวลาให้ตรงกับโบรกเกอร์ของคุณ

`SessionHour` / `SessionMinute` ใช้ **เวลาเซิร์ฟเวอร์ของโบรกเกอร์ (server time)**
ไม่ใช่เวลาไทยและไม่ใช่เวลาเครื่องคุณ — แต่ละโบรกเกอร์ใช้ timezone ไม่เหมือนกัน

วิธีหา: ตลาด NY เปิด 9:30 New York = 20:30 ไทย (ช่วง Daylight Saving)
ดูเวลาเซิร์ฟเวอร์ใน MT5 (มุมบนของหน้าต่าง Market Watch) แล้วเทียบว่า
ขณะนั้นตรงกับเวลาไทยเท่าไร เช่น

| Server timezone ของโบรกเกอร์ | ตั้ง SessionHour:SessionMinute |
|---|---|
| GMT+3 (พบบ่อย เช่น Exness, IC Markets ช่วง DST) | `16:30` (ค่าเริ่มต้น) |
| GMT+2 | `15:30` |
| GMT 0 | `13:30` |

> หมายเหตุ: ช่วงที่สหรัฐฯ ออกจาก Daylight Saving (ราว พ.ย.–มี.ค.)
> ตลาด NY เปิดตรงกับ 21:30 น. ไทย และเวลาเซิร์ฟเวอร์อาจเลื่อน 1 ชั่วโมง
> ขึ้นกับนโยบายโบรกเกอร์ — ควรตรวจสอบและปรับ input ตามฤดูกาล

### Input ทั้งหมด

| Input | ค่าเริ่มต้น | คำอธิบาย |
|---|---|---|
| `SessionHour` / `SessionMinute` | 16:30 | เวลาเปิดตลาด NY ตาม **server time** |
| `WindowMinutes` | 60 | หยุดหา setup หลังเปิดตลาดกี่นาที |
| `RetestBufferPoints` | 30 | ระยะเผื่อ (points) ให้นับว่าราคากลับมารีเทสเส้นแล้ว |
| `MinBodyPoints` | 50 | ขนาดเนื้อเทียนขั้นต่ำของแท่งคอนเฟิร์ม (points) |
| `MinBodyRatio` | 0.60 | สัดส่วน body/range ขั้นต่ำ (กรองแท่ง doji/ไส้ยาว) |
| `SLBufferPoints` | 30 | ระยะเผื่อ SL ใต้/เหนือแท่งคอนเฟิร์ม (points) |
| `RiskRewardRatio` | 2.0 | TP = ระยะ SL × ค่านี้ |
| `AllowBuy` / `AllowSell` | true | เปิด/ปิดการเทรดแต่ละฝั่ง |
| `UseRiskPercent` | true | คำนวณ lot จาก % ความเสี่ยง (false = ใช้ `FixedLot`) |
| `RiskPercent` | 1.0 | % ของ balance ที่เสี่ยงต่อไม้ |
| `FixedLot` | 0.01 | lot คงที่ เมื่อปิด `UseRiskPercent` |
| `MaxTradesPerDay` | 1 | จำนวนไม้สูงสุดต่อวัน |
| `MagicNumber` | 20260611 | เลขแยกออเดอร์ของ EA |
| `DrawRangeLines` | true | วาดเส้น High/Low ของกรอบบนกราฟ |

> ค่า points: ทอง (XAUUSD) ทศนิยม 2 ตำแหน่ง → 30 points = $0.30
> ควรปรับ `RetestBufferPoints` / `MinBodyPoints` ให้เหมาะกับ symbol และความผันผวน
> โดย backtest ใน Strategy Tester (โหมด "Every tick based on real ticks") ก่อนใช้เงินจริง

### Disclaimer

โค้ดนี้จัดทำเพื่อการศึกษา การเทรดมีความเสี่ยง ควรทดสอบบนบัญชี demo
และ backtest ให้มั่นใจก่อนใช้กับบัญชีจริงเสมอ
