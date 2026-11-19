import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'discovery.dart';
import 'models.dart';
import 'session.dart';
import 'ui_chat.dart';

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final name = TextEditingController(text: app.myName);
  final ip = TextEditingController(text: '192.168.43.1');
  final finder = Finder();
  String? err;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    finder.onChange = () {
      if (mounted) setState(() {});
    };
    finder.start().catchError((_) {});
    _prep();
  }

  @override
  void dispose() {
    finder.stop();
    name.dispose();
    ip.dispose();
    super.dispose();
  }

  Future<void> _prep() async {
    try {
      final g = await NetworkInfo().getWifiGatewayIP();
      if (g != null && mounted) ip.text = g;
    } catch (_) {}
  }

  Future<void> _go(bool host, {String? to}) async {
    final n = name.text.trim();
    if (n.isEmpty) {
      setState(() => err = 'আগে আপনার নাম লিখুন');
      return;
    }
    app.setName(n);
    setState(() {
      err = null;
      busy = true;
    });
    try {
      if (host) {
        await app.startHost();
      } else {
        await app.startJoin((to ?? ip.text).trim());
      }
      if (!mounted) return;
      setState(() => busy = false);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const MainPage()));
    } catch (e) {
      await app.leave();
      if (mounted) setState(() => err = 'সংযোগ হয়নি: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final hosts = finder.found.entries.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('HotspotLink')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'আপনার নাম', border: OutlineInputBorder())),
        const SizedBox(height: 20),
        const Text('একজন হটস্পট চালু করে "হোস্ট" চাপুন। বাকিরা সেই হটস্পটে কানেক্ট হয়ে নিচে হোস্ট বেছে নিন।'),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: busy ? null : () => _go(true),
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('হোস্ট (আমি হটস্পট দিচ্ছি)')),
        const Divider(height: 36),
        const Text('কাছের হোস্ট', style: TextStyle(fontWeight: FontWeight.bold)),
        if (hosts.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('খোঁজা হচ্ছে… (আগে হটস্পটের Wi-Fi তে কানেক্ট হন)')),
        for (final h in hosts)
          Card(
            child: ListTile(
              leading: const Icon(Icons.wifi),
              title: Text(h.value),
              subtitle: Text(h.key),
              trailing: FilledButton(
                  onPressed: busy ? null : () => _go(false, to: h.key), child: const Text('জয়েন')),
            ),
          ),
        const Divider(height: 36),
        const Text('খুঁজে না পেলে IP দিন', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
            controller: ip,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'হোস্টের IP', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
            onPressed: busy ? null : () => _go(false),
            icon: const Icon(Icons.login),
            label: const Text('IP দিয়ে জয়েন')),
        if (busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
        if (err != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(err!, style: const TextStyle(color: Colors.red))),
      ]),
    );
  }
}

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  Future<void> _leave(BuildContext ctx) async {
    final ok = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
              title: const Text('সংযোগ বিচ্ছিন্ন করবেন?'),
              content: const Text('হোস্ট বের হলে সবার সংযোগ কেটে যাবে। চ্যাট হিস্টোরি থেকে যাবে।'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('না')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('হ্যাঁ')),
              ],
            ));
    if (ok == true) {
      await app.leave();
      if (ctx.mounted) Navigator.pop(ctx);
    }
  }

  String _status() {
    if (!app.online) return 'পুনরায় সংযোগ হচ্ছে…';
    if (app.hub != null) return 'হোস্ট • IP: ${app.hubIps.join(', ')}';
    return 'সংযুক্ত';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) _leave(context);
      },
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final ids = app.threadIds;
          return Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('HotspotLink'),
                Text(_status(), style: const TextStyle(fontSize: 12)),
              ]),
              actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => _leave(context))],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const NewGroupPage())),
              child: const Icon(Icons.group_add),
            ),
            body: ListView.builder(
              itemCount: ids.length,
              itemBuilder: (c, i) => _tile(c, ids[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext c, String t) {
    final last = app.store.last(t);
    final un = app.store.unread[t] ?? 0;
    final isGroup = t == 'all' || t.startsWith('g:');
    final title = app.titleOf(t);
    return ListTile(
      leading: Stack(children: [
        CircleAvatar(
            child: isGroup
                ? const Icon(Icons.groups)
                : Text(title.isEmpty ? '?' : title.characters.first.toUpperCase())),
        if (!isGroup && app.isOnline(t))
          const Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(radius: 5, backgroundColor: Colors.green)),
      ]),
      title: Text(title),
      subtitle: Text(last == null ? (isGroup ? 'গ্রুপ' : (app.isOnline(t) ? 'অনলাইন' : 'অফলাইন')) : previewOf(last),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (last != null) Text(hm(last.ts), style: const TextStyle(fontSize: 11)),
        if (un > 0)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.primary, borderRadius: BorderRadius.circular(10)),
            child: Text('$un', style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
      ]),
      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ChatPage(thread: t))),
    );
  }
}

class NewGroupPage extends StatefulWidget {
  const NewGroupPage({super.key});
  @override
  State<NewGroupPage> createState() => _NewGroupPageState();
}

class _NewGroupPageState extends State<NewGroupPage> {
  final name = TextEditingController();
  final sel = <String>{};

  @override
  Widget build(BuildContext context) {
    final ids = app.contactIds;
    return Scaffold(
      appBar: AppBar(title: const Text('নতুন গ্রুপ')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (name.text.trim().isEmpty || sel.isEmpty) {
            app.onNotice?.call('গ্রুপের নাম দিন ও সদস্য বাছাই করুন');
            return;
          }
          final t = app.createGroup(name.text.trim(), sel.toList());
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => ChatPage(thread: t)));
        },
        child: const Icon(Icons.check),
      ),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
                controller: name,
                decoration:
                    const InputDecoration(labelText: 'গ্রুপের নাম', border: OutlineInputBorder()))),
        Expanded(
          child: ListView(children: [
            for (final id in ids)
              CheckboxListTile(
                value: sel.contains(id),
                title: Text(app.nameOf(id)),
                subtitle: Text(app.isOnline(id) ? 'অনলাইন' : 'অফলাইন'),
                onChanged: (v) => setState(() => v == true ? sel.add(id) : sel.remove(id)),
              ),
          ]),
        ),
      ]),
    );
  }
}
