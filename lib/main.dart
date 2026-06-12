
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DebtProApp());
}

class DebtProApp extends StatelessWidget {
  const DebtProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دفتر الديون برو صورة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1267E3)),
        scaffoldBackgroundColor: const Color(0xFFF4F8FF),
      ),
      home: const Directionality(textDirection: TextDirection.rtl, child: HomePage()),
    );
  }
}

enum EntryType { debt, payment, note }

class Customer {
  final String id;
  String name;
  String phone;
  String address;
  String note;
  double limit;
  final int createdAt;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.note,
    required this.limit,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'phone': phone, 'address': address,
    'note': note, 'limit': limit, 'createdAt': createdAt,
  };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    phone: j['phone'] ?? '',
    address: j['address'] ?? '',
    note: j['note'] ?? '',
    limit: (j['limit'] ?? 0).toDouble(),
    createdAt: j['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
  );
}

class LedgerEntry {
  final String id;
  final String customerId;
  final EntryType type;
  final double amount;
  final String details;
  final int date;
  final int dueDate;

  LedgerEntry({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.details,
    required this.date,
    required this.dueDate,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'customerId': customerId, 'type': type.name, 'amount': amount,
    'details': details, 'date': date, 'dueDate': dueDate,
  };

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
    id: j['id'] ?? '',
    customerId: j['customerId'] ?? '',
    type: j['type'] == 'payment' ? EntryType.payment : (j['type'] == 'note' ? EntryType.note : EntryType.debt),
    amount: (j['amount'] ?? 0).toDouble(),
    details: j['details'] ?? '',
    date: j['date'] ?? DateTime.now().millisecondsSinceEpoch,
    dueDate: j['dueDate'] ?? 0,
  );
}

enum MainTab { dashboard, customers, due }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Random rnd = Random();
  List<Customer> customers = [];
  List<LedgerEntry> entries = [];
  MainTab tab = MainTab.dashboard;
  String query = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  String id() => '${DateTime.now().millisecondsSinceEpoch}_${rnd.nextInt(999999)}';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final c = p.getString('pro_customers_v1');
      final e = p.getString('pro_entries_v1');
      if (c != null) customers = (jsonDecode(c) as List).map((x) => Customer.fromJson(Map<String,dynamic>.from(x))).toList();
      if (e != null) entries = (jsonDecode(e) as List).map((x) => LedgerEntry.fromJson(Map<String,dynamic>.from(x))).toList();
      setState(() {});
    } catch (_) {}
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('pro_customers_v1', jsonEncode(customers.map((e) => e.toJson()).toList()));
    await p.setString('pro_entries_v1', jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  double debts([String? cid]) => entries.where((e) => e.type == EntryType.debt && (cid == null || e.customerId == cid)).fold(0, (a,e)=>a+e.amount);
  double pays([String? cid]) => entries.where((e) => e.type == EntryType.payment && (cid == null || e.customerId == cid)).fold(0, (a,e)=>a+e.amount);
  double balance([String? cid]) => debts(cid) - pays(cid);

  List<LedgerEntry> customerEntries(String cid) {
    final list = entries.where((e) => e.customerId == cid).toList();
    list.sort((a,b) => a.date.compareTo(b.date));
    return list;
  }

  int overdueCount() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return entries.where((e) => e.type == EntryType.debt && e.dueDate > 0 && e.dueDate < now).length;
  }

  List<Customer> filtered() {
    final list = [...customers];
    list.sort((a,b)=>balance(b.id).compareTo(balance(a.id)));
    final q = query.trim();
    if (q.isEmpty) return list;
    return list.where((c) => c.name.contains(q) || c.phone.contains(q) || c.address.contains(q) || c.note.contains(q)).toList();
  }

  String money(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  String dmy(int ts) {
    if (ts == 0) return '--';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2,'0');
    return '${d.year}/${two(d.month)}/${two(d.day)}';
  }
  String dt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2,'0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  void msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s, textAlign: TextAlign.center), behavior: SnackBarBehavior.floating));

  Future<void> addOrEditCustomer([Customer? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final phone = TextEditingController(text: c?.phone ?? '');
    final address = TextEditingController(text: c?.address ?? '');
    final note = TextEditingController(text: c?.note ?? '');
    final limit = TextEditingController(text: c == null || c.limit == 0 ? '' : money(c.limit));

    await showDialog(context: context, builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(c == null ? 'إضافة عميل' : 'تعديل عميل'),
        content: SingleChildScrollView(child: Column(children: [
          field(name, 'اسم العميل', Icons.person),
          gap(),
          field(phone, 'الهاتف', Icons.phone, keyboard: TextInputType.phone),
          gap(),
          field(address, 'العنوان', Icons.location_on),
          gap(),
          field(limit, 'حد ائتماني اختياري', Icons.credit_score, keyboard: const TextInputType.numberWithOptions(decimal: true)),
          gap(),
          field(note, 'ملاحظات', Icons.note_alt),
        ])),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () async {
            if (name.text.trim().isEmpty) { msg('اكتب اسم العميل'); return; }
            final lim = double.tryParse(limit.text.trim().replaceAll(',', '.')) ?? 0;
            if (c == null) {
              customers.add(Customer(id: id(), name: name.text.trim(), phone: phone.text.trim(), address: address.text.trim(), note: note.text.trim(), limit: lim, createdAt: DateTime.now().millisecondsSinceEpoch));
            } else {
              c.name = name.text.trim(); c.phone = phone.text.trim(); c.address = address.text.trim(); c.note = note.text.trim(); c.limit = lim;
            }
            await save();
            if (!mounted) return;
            Navigator.pop(context); setState(() {}); msg('تم الحفظ');
          }, child: const Text('حفظ')),
        ],
      ),
    ));
  }

  Future<void> addEntry(Customer c, EntryType type) async {
    final amount = TextEditingController();
    final details = TextEditingController();
    DateTime? due;

    await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (context, setD) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(type == EntryType.debt ? 'تسجيل دين' : type == EntryType.payment ? 'تسجيل تسديد' : 'إضافة ملاحظة'),
        content: SingleChildScrollView(child: Column(children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: soft(16), child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF063B63)))),
          gap(),
          if (type != EntryType.note) field(amount, 'المبلغ', Icons.payments, keyboard: const TextInputType.numberWithOptions(decimal: true)),
          if (type != EntryType.note) gap(),
          field(details, 'البيان / الملاحظة', Icons.description),
          if (type == EntryType.debt) ...[
            gap(),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDate: DateTime.now(),
                );
                if (picked != null) setD(() => due = picked);
              },
              icon: const Icon(Icons.event),
              label: Text(due == null ? 'تاريخ استحقاق اختياري' : 'الاستحقاق: ${dmy(due!.millisecondsSinceEpoch)}'),
            ),
          ],
        ])),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () async {
            double val = 0;
            if (type != EntryType.note) {
              val = double.tryParse(amount.text.trim().replaceAll(',', '.')) ?? 0;
              if (val <= 0) { msg('اكتب مبلغًا صحيحًا'); return; }
            }
            entries.add(LedgerEntry(id: id(), customerId: c.id, type: type, amount: val, details: details.text.trim(), date: DateTime.now().millisecondsSinceEpoch, dueDate: due?.millisecondsSinceEpoch ?? 0));
            await save();
            if (!mounted) return;
            Navigator.pop(context); setState(() {}); msg('تم التسجيل');
          }, child: const Text('حفظ')),
        ],
      ),
    )));
  }

  Future<bool> confirm(String title, String text) async {
    final r = await showDialog<bool>(context: context, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: AlertDialog(
      title: Text(title), content: Text(text),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('إلغاء')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD90429)), onPressed: ()=>Navigator.pop(context,true), child: const Text('حذف')),
      ],
    )));
    return r == true;
  }

  Future<void> deleteCustomer(Customer c) async {
    if (!await confirm('حذف العميل؟', 'سيتم حذف العميل وجميع الحركات المرتبطة به.')) return;
    customers.removeWhere((x)=>x.id==c.id);
    entries.removeWhere((x)=>x.customerId==c.id);
    await save(); setState(() {}); msg('تم الحذف');
  }

  Future<void> deleteEntry(LedgerEntry e) async {
    if (!await confirm('حذف الحركة؟', 'سيتم حذف هذه الحركة من كشف الحساب.')) return;
    entries.removeWhere((x)=>x.id==e.id);
    await save(); setState(() {}); msg('تم حذف الحركة');
  }

  TextField field(TextEditingController c, String label, IconData icon, {TextInputType? keyboard}) => TextField(
    controller: c,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
  );
  SizedBox gap() => const SizedBox(height: 10);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: tab == MainTab.customers ? FloatingActionButton.extended(onPressed: ()=>addOrEditCustomer(), icon: const Icon(Icons.person_add), label: const Text('عميل جديد')) : null,
      body: SafeArea(child: Column(children: [
        header(),
        nav(),
        Expanded(child: tab == MainTab.dashboard ? dashboard() : tab == MainTab.customers ? customersPage() : duePage()),
      ])),
    );
  }

  Widget header() => Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(15),
    decoration: card(28),
    child: Column(children: [
      Row(children: [
        Container(width: 54, height: 54, decoration: BoxDecoration(gradient: const LinearGradient(colors:[Color(0xFF00A8FF), Color(0xFF1267E3)]), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 30)),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('دفتر الديون برو', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Color(0xFF063B63))),
          Text('إدارة احترافية للديون والتسديدات', style: TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w700)),
        ])),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: mini('الديون', money(debts()), const Color(0xFFE63946), Icons.trending_up)),
        const SizedBox(width: 8),
        Expanded(child: mini('التسديد', money(pays()), const Color(0xFF00A96B), Icons.done_all)),
        const SizedBox(width: 8),
        Expanded(child: mini('الرصيد', money(balance()), const Color(0xFF1267E3), Icons.calculate)),
      ])
    ]),
  );

  Widget mini(String label, String value, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
    decoration: soft(18),
    child: Column(children: [
      Icon(icon, color: color, size: 20),
      Text(label, style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w900, fontSize: 12)),
      FittedBox(child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18))),
    ]),
  );

  Widget nav() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Container(
      padding: const EdgeInsets.all(5),
      decoration: soft(18),
      child: Row(children: [
        navBtn('الرئيسية', MainTab.dashboard, Icons.dashboard),
        navBtn('العملاء', MainTab.customers, Icons.people),
        navBtn('المستحق', MainTab.due, Icons.event_busy),
      ]),
    ),
  );

  Widget navBtn(String text, MainTab t, IconData icon) {
    final active = tab == t;
    return Expanded(child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: ()=>setState(()=>tab=t),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(color: active ? const Color(0xFF1267E3) : Colors.transparent, borderRadius: BorderRadius.circular(15)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: active ? Colors.white : const Color(0xFF50677E)),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: active ? Colors.white : const Color(0xFF50677E), fontWeight: FontWeight.w900, fontSize: 13)),
        ]),
      ),
    ));
  }

  Widget dashboard() {
    final active = customers.where((c)=>balance(c.id)>0).length;
    final clean = customers.where((c)=>balance(c.id)<=0 && (debts(c.id)>0 || pays(c.id)>0)).length;
    Customer? biggest;
    if (customers.isNotEmpty) {
      biggest = customers.reduce((a,b)=>balance(a.id) >= balance(b.id) ? a : b);
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      kpi('عدد العملاء', customers.length.toString(), Icons.people, const Color(0xFF1267E3)),
      kpi('عملاء عليهم رصيد', active.toString(), Icons.warning_amber, const Color(0xFFE63946)),
      kpi('عملاء مسددين', clean.toString(), Icons.verified, const Color(0xFF00A96B)),
      kpi('ديون متأخرة', overdueCount().toString(), Icons.event_busy, const Color(0xFFFF9800)),
      if (biggest != null)
        Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(15), decoration: card(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('أكبر رصيد مستحق', style: TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          Text(biggest.name, style: const TextStyle(color: Color(0xFF063B63), fontSize: 20, fontWeight: FontWeight.w900)),
          Text('${money(balance(biggest.id))} دينار', style: const TextStyle(color: Color(0xFFE63946), fontSize: 28, fontWeight: FontWeight.w900)),
        ])),
    ]);
  }

  Widget kpi(String title, String value, IconData icon, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: card(22),
    child: Row(children: [
      CircleAvatar(backgroundColor: color.withOpacity(.12), child: Icon(icon, color: color)),
      const SizedBox(width: 12),
      Expanded(child: Text(title, style: const TextStyle(color: Color(0xFF063B63), fontWeight: FontWeight.w900, fontSize: 16))),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 24)),
    ]),
  );

  Widget customersPage() {
    final list = filtered();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12,12,12,8), child: TextField(
        onChanged: (v)=>setState(()=>query=v),
        decoration: InputDecoration(hintText: 'بحث بالاسم أو الهاتف أو العنوان', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none)),
      )),
      Expanded(child: list.isEmpty ? empty('لا يوجد عملاء بعد.\nاضغط عميل جديد للبدء.') : ListView.builder(padding: const EdgeInsets.fromLTRB(12,4,12,90), itemCount: list.length, itemBuilder: (_,i)=>customerCard(list[i]))),
    ]);
  }

  Widget customerCard(Customer c) {
    final bal = balance(c.id);
    final col = bal > 0 ? const Color(0xFFE63946) : const Color(0xFF00A96B);
    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(13), decoration: card(22), child: InkWell(
      onTap: ()=>openCustomer(c),
      child: Column(children: [
        Row(children: [
          CircleAvatar(radius: 24, backgroundColor: const Color(0xFFE8F8FF), child: Text(c.name.isEmpty ? '؟' : c.name.characters.first, style: const TextStyle(fontWeight: FontWeight.w900))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: const TextStyle(color: Color(0xFF063B63), fontSize: 18, fontWeight: FontWeight.w900)),
            if (c.phone.isNotEmpty) Text(c.phone, style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w700)),
            if (c.address.isNotEmpty) Text(c.address, style: const TextStyle(color: Color(0xFF6B8198), fontSize: 12)),
          ])),
          PopupMenuButton<String>(onSelected: (v){ if(v=='edit') addOrEditCustomer(c); if(v=='del') deleteCustomer(c); }, itemBuilder: (_)=> const [
            PopupMenuItem(value:'edit', child: Text('تعديل')),
            PopupMenuItem(value:'del', child: Text('حذف')),
          ]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: pill('دين', money(debts(c.id)), const Color(0xFFE63946))),
          const SizedBox(width: 7),
          Expanded(child: pill('تسديد', money(pays(c.id)), const Color(0xFF00A96B))),
          const SizedBox(width: 7),
          Expanded(child: pill('رصيد', money(bal), col)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: ()=>addEntry(c, EntryType.debt), icon: const Icon(Icons.add), label: const Text('دين'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(onPressed: ()=>addEntry(c, EntryType.payment), icon: const Icon(Icons.check), label: const Text('تسديد'))),
        ]),
      ]),
    ));
  }

  Widget pill(String label, String val, Color c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
    decoration: soft(16),
    child: Column(children: [
      Text(label, style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w900, fontSize: 12)),
      FittedBox(child: Text(val, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 17))),
    ]),
  );

  Widget duePage() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = entries.where((e)=>e.type==EntryType.debt && e.dueDate>0).toList()..sort((a,b)=>a.dueDate.compareTo(b.dueDate));
    if (due.isEmpty) return empty('لا توجد ديون لها تاريخ استحقاق.');
    return ListView(padding: const EdgeInsets.all(12), children: due.map((e) {
      final c = customers.where((x)=>x.id==e.customerId).cast<Customer?>().firstOrNull;
      final late = e.dueDate < now;
      return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(13), decoration: card(22), child: Row(children: [
        CircleAvatar(backgroundColor: (late ? const Color(0xFFE63946) : const Color(0xFFFF9800)).withOpacity(.12), child: Icon(Icons.event_busy, color: late ? const Color(0xFFE63946) : const Color(0xFFFF9800))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c?.name ?? 'عميل محذوف', style: const TextStyle(color: Color(0xFF063B63), fontWeight: FontWeight.w900, fontSize: 16)),
          Text('الاستحقاق: ${dmy(e.dueDate)}', style: TextStyle(color: late ? const Color(0xFFE63946) : const Color(0xFF6B8198), fontWeight: FontWeight.w900)),
          if(e.details.isNotEmpty) Text(e.details, style: const TextStyle(color: Color(0xFF6B8198))),
        ])),
        Text(money(e.amount), style: const TextStyle(color: Color(0xFFE63946), fontWeight: FontWeight.w900, fontSize: 18)),
      ]));
    }).toList());
  }

  Future<void> openCustomer(Customer c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_)=>Directionality(textDirection: TextDirection.rtl, child: CustomerDetails(
      customer: c,
      list: customerEntries(c.id),
      money: money,
      dt: dt,
      dmy: dmy,
      debt: debts(c.id),
      pay: pays(c.id),
      bal: balance(c.id),
      onDebt: ()=>addEntry(c, EntryType.debt),
      onPay: ()=>addEntry(c, EntryType.payment),
      onNote: ()=>addEntry(c, EntryType.note),
      onDelete: deleteEntry,
      statementText: ()=>statementText(c),
      onShareText: ()=>shareStatementText(c),
      onReminder: ()=>shareReminder(c),
      onShareImage: ()=>shareStatementImage(c),
    ))));
    setState(() {});
  }

  String statementText(Customer c) {
    final b = StringBuffer();
    b.writeln('كشف حساب: ${c.name}');
    if (c.phone.isNotEmpty) b.writeln('الهاتف: ${c.phone}');
    b.writeln('----------------------');
    double run = 0;
    for (final e in customerEntries(c.id)) {
      if (e.type == EntryType.debt) run += e.amount;
      if (e.type == EntryType.payment) run -= e.amount;
      b.writeln('${dt(e.date)} | ${e.type == EntryType.debt ? 'دين' : e.type == EntryType.payment ? 'تسديد' : 'ملاحظة'} | ${money(e.amount)} | الرصيد ${money(run)} | ${e.details}');
    }
    b.writeln('----------------------');
    b.writeln('إجمالي الدين: ${money(debts(c.id))}');
    b.writeln('إجمالي التسديد: ${money(pays(c.id))}');
    b.writeln('الرصيد: ${money(balance(c.id))}');
    return b.toString();
  }

  String reminderText(Customer c) {
    return 'السلام عليكم،\n'
        'نذكركم بأن الرصيد المستحق عليكم هو ${money(balance(c.id))} دينار.\n'
        'إجمالي الدين: ${money(debts(c.id))} دينار.\n'
        'إجمالي التسديد: ${money(pays(c.id))} دينار.\n'
        'يرجى التسديد عند الإمكان.\n'
        'مع الشكر.';
  }

  Future<void> shareStatementText(Customer c) async {
    await Share.share(statementText(c), subject: 'كشف حساب ${c.name}');
  }

  Future<void> shareReminder(Customer c) async {
    await Share.share(reminderText(c), subject: 'تذكير رصيد ${c.name}');
  }

  Future<void> shareStatementImage(Customer c) async {
    try {
      final controller = ScreenshotController();
      final bytes = await controller.captureFromWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            color: Colors.white,
            child: StatementImageCard(
              customer: c,
              entries: customerEntries(c.id),
              money: money,
              dt: dt,
              debt: debts(c.id),
              pay: pays(c.id),
              bal: balance(c.id),
            ),
          ),
        ),
        delay: const Duration(milliseconds: 150),
        pixelRatio: 2.5,
      );

      final dir = await getTemporaryDirectory();
      final cleanName = c.name.replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9]+'), '_');
      final file = File('${dir.path}/statement_$cleanName.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'كشف حساب ${c.name}',
        subject: 'كشف حساب ${c.name}',
      );
    } catch (e) {
      msg('تعذر إنشاء الصورة. جرّب مشاركة كشف الحساب كنص.');
    }
  }


  Widget empty(String text) => Center(child: Padding(padding: const EdgeInsets.all(22), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w800, height: 1.8))));
  BoxDecoration card(double r) => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(r), border: Border.all(color: const Color(0xFFDCEEFA)), boxShadow:[BoxShadow(color: const Color(0xFF0069AA).withOpacity(.08), blurRadius: 24, offset: const Offset(0,10))]);
  BoxDecoration soft(double r) => BoxDecoration(color: const Color(0xFFF7FCFF), borderRadius: BorderRadius.circular(r), border: Border.all(color: const Color(0xFFDCEEFA)));
}


class StatementImageCard extends StatelessWidget {
  final Customer customer;
  final List<LedgerEntry> entries;
  final String Function(double) money;
  final String Function(int) dt;
  final double debt;
  final double pay;
  final double bal;

  const StatementImageCard({
    super.key,
    required this.customer,
    required this.entries,
    required this.money,
    required this.dt,
    required this.debt,
    required this.pay,
    required this.bal,
  });

  @override
  Widget build(BuildContext context) {
    double running = 0;
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final shown = sorted.length > 18 ? sorted.sublist(sorted.length - 18) : sorted;

    return Container(
      width: 900,
      color: const Color(0xFFF4F8FF),
      padding: const EdgeInsets.all(28),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFDCEEFA), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0069AA).withOpacity(.10),
              blurRadius: 30,
              offset: const Offset(0, 12),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF00A8FF), Color(0xFF1267E3)]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 38),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('كشف حساب', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF063B63))),
                      Text(customer.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1267E3))),
                      if (customer.phone.isNotEmpty)
                        Text(customer.phone, style: const TextStyle(fontSize: 17, color: Color(0xFF6B8198), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _summary('إجمالي الدين', money(debt), const Color(0xFFE63946)),
                const SizedBox(width: 12),
                _summary('إجمالي التسديد', money(pay), const Color(0xFF00A96B)),
                const SizedBox(width: 12),
                _summary('الرصيد', money(bal), const Color(0xFF1267E3)),
              ],
            ),
            const SizedBox(height: 24),
            _tableHeader(),
            if (shown.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                child: const Text('لا توجد حركات لهذا العميل.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Color(0xFF6B8198), fontWeight: FontWeight.w800)),
              )
            else
              ...shown.map((e) {
                if (e.type == EntryType.debt) running += e.amount;
                if (e.type == EntryType.payment) running -= e.amount;
                return _row(e, running);
              }),
            if (sorted.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'تم عرض آخر ${shown.length} حركة من أصل ${sorted.length} حركة',
                  style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FCFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFDCEEFA)),
              ),
              child: Text(
                'تاريخ الكشف: ${dt(DateTime.now().millisecondsSinceEpoch)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FCFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDCEEFA)),
        ),
        child: Column(
          children: [
            Text(title, style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 6),
            FittedBox(child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 28))),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1267E3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('التاريخ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
          Expanded(flex: 2, child: Text('النوع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
          Expanded(flex: 2, child: Text('المبلغ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
          Expanded(flex: 2, child: Text('الرصيد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
          Expanded(flex: 3, child: Text('البيان', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
        ],
      ),
    );
  }

  Widget _row(LedgerEntry e, double running) {
    final isDebt = e.type == EntryType.debt;
    final isPay = e.type == EntryType.payment;
    final color = isDebt ? const Color(0xFFE63946) : isPay ? const Color(0xFF00A96B) : const Color(0xFF7B61FF);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE9F3FB))),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(dt(e.date), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          Expanded(flex: 2, child: Text(isDebt ? 'دين' : isPay ? 'تسديد' : 'ملاحظة', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14))),
          Expanded(flex: 2, child: Text(e.type == EntryType.note ? '-' : money(e.amount), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15))),
          Expanded(flex: 2, child: Text(money(running), style: const TextStyle(color: Color(0xFF063B63), fontWeight: FontWeight.w900, fontSize: 15))),
          Expanded(flex: 3, child: Text(e.details.isEmpty ? '-' : e.details, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}


extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class CustomerDetails extends StatefulWidget {
  final Customer customer;
  final List<LedgerEntry> list;
  final String Function(double) money;
  final String Function(int) dt;
  final String Function(int) dmy;
  final double debt;
  final double pay;
  final double bal;
  final Future<void> Function() onDebt;
  final Future<void> Function() onPay;
  final Future<void> Function() onNote;
  final Future<void> Function(LedgerEntry) onDelete;
  final String Function() statementText;
  final Future<void> Function() onShareText;
  final Future<void> Function() onReminder;
  final Future<void> Function() onShareImage;

  const CustomerDetails({super.key, required this.customer, required this.list, required this.money, required this.dt, required this.dmy, required this.debt, required this.pay, required this.bal, required this.onDebt, required this.onPay, required this.onNote, required this.onDelete, required this.statementText, required this.onShareText, required this.onReminder, required this.onShareImage});

  @override
  State<CustomerDetails> createState() => _CustomerDetailsState();
}

class _CustomerDetailsState extends State<CustomerDetails> {
  @override
  Widget build(BuildContext context) {
    final reverse = [...widget.list]..sort((a,b)=>b.date.compareTo(a.date));
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      appBar: AppBar(
        title: Text(widget.customer.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: widget.statementText()));
                if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ كشف الحساب')));
              }
              if (v == 'shareText') await widget.onShareText();
              if (v == 'reminder') await widget.onReminder();
              if (v == 'image') await widget.onShareImage();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('نسخ كشف الحساب')),
              PopupMenuItem(value: 'shareText', child: Text('مشاركة كشف الحساب كنص')),
              PopupMenuItem(value: 'reminder', child: Text('إرسال تذكير')),
              PopupMenuItem(value: 'image', child: Text('مشاركة كشف الحساب كصورة')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () async { await widget.onDebt(); if(context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.add), label: const Text('دين'))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton.icon(onPressed: () async { await widget.onPay(); if(context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.check), label: const Text('تسديد'))),
        const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: () async { await widget.onNote(); if(context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.note_add)),
      ]))),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Container(padding: const EdgeInsets.all(14), decoration: card(24), child: Column(children: [
          if(widget.customer.phone.isNotEmpty) Text(widget.customer.phone, style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: mini('دين', widget.money(widget.debt), const Color(0xFFE63946))),
            const SizedBox(width: 8),
            Expanded(child: mini('تسديد', widget.money(widget.pay), const Color(0xFF00A96B))),
            const SizedBox(width: 8),
            Expanded(child: mini('رصيد', widget.money(widget.bal), const Color(0xFF1267E3))),
          ]),
        ])),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: widget.onShareImage, icon: const Icon(Icons.image), label: const Text('صورة'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: widget.onReminder, icon: const Icon(Icons.notifications_active), label: const Text('تذكير'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: widget.onShareText, icon: const Icon(Icons.share), label: const Text('مشاركة نص'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.statementText()));
            if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ كشف الحساب')));
          }, icon: const Icon(Icons.copy), label: const Text('نسخ'))),
        ]),
        const SizedBox(height: 14),
        const Text('كشف الحساب', style: TextStyle(color: Color(0xFF063B63), fontWeight: FontWeight.w900, fontSize: 20)),
        const SizedBox(height: 8),
        if(reverse.isEmpty) const Padding(padding: EdgeInsets.all(22), child: Text('لا توجد حركات.', textAlign: TextAlign.center))
        else ...reverse.map(entryCard),
      ]),
    );
  }

  Widget mini(String l, String v, Color c) => Container(padding: const EdgeInsets.all(10), decoration: soft(16), child: Column(children: [
    Text(l, style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w900, fontSize: 12)),
    FittedBox(child: Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 18))),
  ]));

  Widget entryCard(LedgerEntry e) {
    final isDebt = e.type == EntryType.debt;
    final isPay = e.type == EntryType.payment;
    final color = isDebt ? const Color(0xFFE63946) : isPay ? const Color(0xFF00A96B) : const Color(0xFF7B61FF);
    return Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(13), decoration: card(20), child: Row(children: [
      CircleAvatar(backgroundColor: color.withOpacity(.12), child: Icon(isDebt ? Icons.trending_up : isPay ? Icons.done_all : Icons.note_alt, color: color)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isDebt ? 'دين' : isPay ? 'تسديد' : 'ملاحظة', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
        Text(widget.dt(e.date), style: const TextStyle(color: Color(0xFF6B8198), fontWeight: FontWeight.w700, fontSize: 12)),
        if(e.dueDate>0) Text('استحقاق: ${widget.dmy(e.dueDate)}', style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.w800, fontSize: 12)),
        if(e.details.isNotEmpty) Text(e.details, style: const TextStyle(color: Color(0xFF102033), fontWeight: FontWeight.w700)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if(e.type != EntryType.note) Text(widget.money(e.amount), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 19)),
        IconButton(onPressed: () async { await widget.onDelete(e); if(context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.delete_outline), color: const Color(0xFFD90429)),
      ]),
    ]));
  }

  BoxDecoration card(double r) => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(r), border: Border.all(color: const Color(0xFFDCEEFA)), boxShadow:[BoxShadow(color: const Color(0xFF0069AA).withOpacity(.08), blurRadius: 22, offset: const Offset(0,9))]);
  BoxDecoration soft(double r) => BoxDecoration(color: const Color(0xFFF7FCFF), borderRadius: BorderRadius.circular(r), border: Border.all(color: const Color(0xFFDCEEFA)));
}
