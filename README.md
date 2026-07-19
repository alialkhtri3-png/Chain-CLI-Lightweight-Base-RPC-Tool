Balance: 0.000022 ETH
⚙️ كيف يعمل؟
يستخدم curl لإرسال طلبات JSON-RPC مباشرة
بدون API Keys
بدون ethers.js أو web3.js
تصميم بسيط وسهل التوسعة
🧩 خارطة الطريق (Roadmap)
[ ] دعم ERC-20 balances
[ ] دعم شبكات إضافية
[ ] تحسين تنسيق الإخراج
[ ] توثيق كامل
[ ] إصدار عام (v1.0)
💡 أهداف المنحة
سيتم استخدام المنحة من أجل:
تحسين هيكلة الكود
إضافة ميزات جديدة
توثيق المشروع بشكل كامل
نشر الأداة كمشروع مفتوح المصدر
دعم منظومة Base بأدوات مطورين خفيفة
📜 الرخصة
MIT
🧩 Chain-CLI – Lightweight Base RPC Tool
Chain CLI هي أداة سطر أوامر خفيفة الوزن تُمكّن المطورين من الاستعلام عن بيانات شبكة Base (وEthereum) مباشرة عبر JSON-RPC،
بدون الحاجة إلى مفاتيح API وبدون استخدام مكتبات Web3 الثقيلة مثل ethers.js أو web3.js.
تم بناء النموذج الأولي وتشغيله محليًا باستخدام Termux.
✨ ماذا يفعل المشروع؟
جلب رقم آخر بلوك (eth_blockNumber)
جلب Chain ID
جلب رصيد ETH لأي عنوان
تحويل الرصيد من Wei إلى ETH
الاتصال المباشر عبر RPC العام
🧠 لماذا Base؟
تم بناء المشروع على شبكة Base لأنها:
منخفضة الرسوم وسريعة
متوافقة بالكامل مع EVM
مثالية للأدوات الخفيفة والنماذج الأولية
مناسبة للمطورين في البيئات محدودة الموارد (مثل Termux)
🛠 الحالة الحالية
Prototype (نموذج أولي)
✅ يعمل محليًا
✅ يدعم الوظائف الأساسية
🔄 قيد التطوير والتحسين
🚀 التثبيت والتشغيل
المتطلبات
Termux أو أي نظام Linux
bash
curl
bc
التثبيت
نسخ التعليمات البرمجية
Bash
mkdir -p ~/bin
mv chain-cli.sh ~/bin/chain-cli
chmod +x ~/bin/chain-cli
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
الاستخدام
نسخ التعليمات البرمجية
Bash
chain base block
chain base chainid
chain base balance 0xADDRESS
chain base balance 0xADDRESS --eth
مثال
نسخ التعليمات البرمجية
Bash
chain base balance 0xABCDEF1234567890ABCDEF1234567890ABCDEF12 --eth
Balance: 0.000022 ETH
⚙️ كيف يعمل؟
يعتمد على curl لإرسال طلبات JSON-RPC
لا يستخدم مفاتيح API
لا يعتمد على مكتبات Web3
تصميم بسيط وسهل التوسعة
🧩 خارطة الطريق (Roadmap)
[ ] دعم أرصدة ERC-20
[ ] دعم شبكات إضافية
[ ] تحسين تنسيق الإخراج
[ ] توثيق كامل
[ ] إصدار عام (v1.0)
💡 أهداف المشروع والمنحة
يهدف المشروع إلى:
توفير أداة خفيفة للمطورين على Base
دعم بيئات التطوير البسيطة (CLI / Termux)
تحسين الهيكلة وإضافة ميزات جديدة
نشر المشروع كمصدر مفتوح
دعم منظومة Base بأدوات مطورين عملية
📜 ## Live Demo

Sovereign Identity Engine V13

Features:
- Wallet Intelligence
- Identity Score
- Passport
- Verifiable Credential
- Signature Verification

