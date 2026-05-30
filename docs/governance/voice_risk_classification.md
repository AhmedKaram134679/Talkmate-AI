# TalkMate AI: Voice Risk Classification 🧬🛡️📉🎙️

يُصنف النظام الصوتي كـ **نظام عالي الخطورة (High-Risk System)**. توثق هذه الوثيقة
العتبات (Thresholds) التي تتطلب تدخلاً دستورياً فورياً.

## 1. عتبات المخاطر التقنية (Technical Thresholds)

| المعيار (Metric)               | مستوى التنبيه (EWS)    | مستوى الخطر الحرج       | الإجراء الدستوري             |
| :----------------------------- | :--------------------- | :---------------------- | :--------------------------- |
| **استهلاك الذاكرة (RAM)**      | +50MB من Baseline      | +100MB من Baseline      | **Auto-Shutdown**            |
| **ارتفاع الحرارة (Thermal)**   | 40°C                   | 45°C                    | **Quality Drop -> Shutdown** |
| **استنزاف البطارية**           | 5% استهلاك في 10 دقائق | 10% استهلاك في 10 دقائق | **Kill-Switch Option**       |
| **أخطاء التدفق (Packet Loss)** | 15%                    | 30%                     | **Audio Degradation -> Cut** |

---

## 2. إشارات الإنذار المبكر (Early Warning Signals - EWS)

يجب على الـ `PredictiveEngine` رصد الأنماط التالية وإصدار إنذار صوتي (Voice
Alarm):

1. **Buffer Bloat**: زيادة مفاجئة في زمن وصول الحزم تشير إلى اختناق الشبكة.
2. **Memory Leak Pattern**: تصاعد مستمر في استهلاك الذاكرة لا يتم تطهيره.
3. **Signal Instability**: تقلب حاد في قوة الإشارة اللاسلكية (WiFi/4G).

---

## 3. شروط الإيقاف التلقائي (Auto-Shutdown Conditions)

يُقتل النظام الصوتي فوراً وبدون تدخل بشري في الحالات التالية:

- وصول الذاكرة إلى مستوى "Critical" المحدد في `AdaptiveController`.
- استمرار تدهور الشبكة (L4 Failure) لأكثر من 15 ثانية متواصلة.
- استلام إشارة "Security Threat" من الـ `Gatekeeper`.
- تحول التطبيق للخلفية (Background) وفشل بروتوكول "Background Audio Permission".

---

**Verified by: Principal Real-Time Systems Architect**
