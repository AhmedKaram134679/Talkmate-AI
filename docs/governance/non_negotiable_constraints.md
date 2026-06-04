# TalkMate AI: Non-Negotiable Constraints (Hard No Rules) 🏁🛡️⛔

تمثل هذه الوثيقة "الخطوط الحمراء" التي لا يُسمح بتجاوزها في معماريّة TalkMate AI.
أي محاولة لكسر هذه القوانين تعتبر فشلاً معمارياً وتتطلب رفض الكود فوراً.

## 1. قوانين الميزات (Feature Constraints)

1. **لا ميزة بدون مفتاح (No Feature without Flag)**: يُحظر دمج أي كود تنفيذي
   (Feature) لا يمكن التحكم في تفعيله وتعطيله عن بُعد عبر الـ Release Manager.
2. **لا ميزة بدون إيقاف (No Feature without Kill Switch)**: يجب أن تمتلك الميزة
   آلية تعطيل فورية (Hard Kill) تعيد النظام للحالة المستقرة السابقة (D1-D3) دون
   الحاجة لإصدار تحديث جديد.
3. **لا ميزة عمياء (No Feature without Metrics)**: يُمنع دمج أي ميزة لا تحتوي على
   مؤشرات رصد (Observability Hooks) تقيس تأثيرها على الذاكرة، الأداء، ونسبة
   الأخطاء.

## 2. قوانين البنية التحتية (Systemic Constraints)

1. **قانون الصندوق المفتوح (Open Box Law)**: لا يُسمح بالاعتماد على مكتبات خارجية
   (Third-party) تعمل كـ "صندوق أسود" لا يمكن رصد سلوكه الداخلي أو التحكم في
   استهلاكه للموارد.
2. **درع الدوائر الكهربائية (Mandatory Circuit Breakers)**: أي نظام يعتمد على
   خدمة خارجية (API, DB, Cloud) يجب أن يمتلكCircuit Breaker يمنع انهيار TalkMate
   AI عند تعثر تلك الخدمة.
3. **التراجع التلقائي (Safe State Rollback)**: يُحظر إجراء أي تعديل في قاعدة
   البيانات لا يدعم التراجع الخلفي (Backward Compatibility) للإصدار السابق من
   التطبيق مباشرة.

## 3. قوانين الأداء والأمان (Performance & Security Constraints)

1. **أولوية الاستقرار (Stability First)**: لا يُقبل أي تحسين في الأداء
   (Speed/Latency) إذا كان يزيد من احتمالية حدوث انهيارات (Crashes) بنسبة تتجاوز
   0.05%.
2. **قدسية الخصوصية (Privacy Sanctity)**: يُمنع رصد أي بيانات سلوكية للمستخدم
   (Behavioral Tracking) يمكن أن تكسر مبدأ "الحد الأدنى من المعرفة"
   (Need-to-Know) الموثق في المرحلة D4.
3. **عزل المراجعة (Isolated Audit)**: لا تُدمج الأكواد السيادية (Critical Risk) إلا
   بعد مراجعة مستقلة من قبل شخصين مختلفين أحدهما Governor.

---

**Failure to comply with these rules is a violation of the Architectural
Integrity of TalkMate AI.**
