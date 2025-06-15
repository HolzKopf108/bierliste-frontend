import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/money_input_formatter.dart';

class Member {
  final String id;
  final String name;
  final int striche;
  final double saldo;
  final bool isWart;

  Member({
    required this.id,
    required this.name,
    required this.striche,
    required this.saldo,
    required this.isWart,
  });

  Member copyWith({int? striche, double? saldo, bool? isWart}) {
    return Member(
      id: id,
      name: name,
      striche: striche ?? this.striche,
      saldo: saldo ?? this.saldo,
      isWart: isWart ?? this.isWart,
    );
  }
}

enum SortOption { alphabet, striche }

class GroupUsersPage extends StatefulWidget {
  final String groupName;

  const GroupUsersPage({super.key, required this.groupName});

  @override
  State<GroupUsersPage> createState() => _GroupUsersPageState();
}

class _GroupUsersPageState extends State<GroupUsersPage> {
  List<Member> _members = [];
  SortOption _sortOption = SortOption.alphabet;
  final double _pricePerStrich = 1.5;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  void _loadMembers() {
    setState(() {
      _members = [
        Member(id: '1', name: 'Max Mustermann', striche: 12, saldo: 18.0, isWart: true),
        Member(id: '2', name: 'Lisa Musterfrau', striche: 0, saldo: -5.0, isWart: true),
        Member(id: '3', name: 'Alex Beispiel', striche: 8, saldo: 12.0, isWart: false),
      ];
    });
  }

  void _sortMembers() {
    if (_sortOption == SortOption.alphabet) {
      _members.sort((a, b) => a.name.compareTo(b.name));
    } else {
      _members.sort((b, a) {
        final cmp = a.striche.compareTo(b.striche);
        if (cmp != 0) return cmp;
        return a.saldo.compareTo(b.saldo);
      });
    }
  }

  void _showStrichDialog(Member member) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Striche für ${member.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Anzahl Striche',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final count = int.tryParse(controller.text.trim()) ?? 0;
              if (count <= 0) return;

              final additionalSaldo = count * _pricePerStrich;
              double newSaldo = member.saldo;
              int newStriche = member.striche;

              if (member.saldo < 0) {
                newSaldo += additionalSaldo;
                if (newSaldo > 0) {
                  final extraStriche = (newSaldo / _pricePerStrich).floor();
                  newStriche += extraStriche;
                  newSaldo -= extraStriche * _pricePerStrich;
                }
              } else {
                newStriche += count;
                newSaldo += additionalSaldo;
              }

              setState(() {
                final index = _members.indexWhere((m) => m.id == member.id);
                _members[index] = member.copyWith(striche: newStriche, saldo: newSaldo);
              });

              Navigator.pop(context);
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
  }

  void _showGeldAbziehenDialog(Member member) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Betrag abziehen von ${member.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Betrag (€)',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
          inputFormatters: [MoneyInputFormatter()],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final rawInput = controller.text.replaceAll(',', '.');
              final value = double.tryParse(rawInput) ?? 0;
              if (value <= 0) return;

              double newSaldo = member.saldo - value;
              int newStriche = member.striche;

              if (newSaldo < 0) {
                newStriche = 0;
              } else {
                final possibleStriche = (newSaldo / _pricePerStrich).floor();
                newStriche = possibleStriche;
                newSaldo = newStriche * _pricePerStrich;
              }

              setState(() {
                final index = _members.indexWhere((m) => m.id == member.id);
                _members[index] = member.copyWith(striche: newStriche, saldo: newSaldo);
              });

              Navigator.pop(context);
            },
            child: const Text('Abziehen'),
          ),
        ],
      ),
    );
  }

  bool get _isCurrentUserWart => true;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    _sortMembers();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mitgliederübersicht'),
        actions: [
          IconButton(
            icon: Icon(Icons.sort_by_alpha,
                color: _sortOption == SortOption.alphabet ? Colors.white : Colors.white54),
            onPressed: () => setState(() => _sortOption = SortOption.alphabet),
          ),
          IconButton(
            icon: Icon(Icons.local_drink,
                color: _sortOption == SortOption.striche ? Colors.white : Colors.white54),
            onPressed: () => setState(() => _sortOption = SortOption.striche),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        itemCount: _members.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final member = _members[index];
          final saldoFormatted = member.saldo.toStringAsFixed(2).replaceAll('.', ',');

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.person),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              member.name,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (member.isWart)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Bierlistenwart',
                                style: TextStyle(fontSize: 9, color: Colors.black),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('🍺 ${member.striche}   |   € $saldoFormatted',
                          style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'strich') _showStrichDialog(member);
                    if (value == 'geld') _showGeldAbziehenDialog(member);
                    if (value == 'toggleWart') {
                      setState(() {
                        final index = _members.indexWhere((m) => m.id == member.id);
                        _members[index] = member.copyWith(isWart: !member.isWart);
                      });
                    }
                  },
                  itemBuilder: (_) {
                    final isCurrentUserWart = _isCurrentUserWart;
                    final isOtherWart = member.isWart;

                    return [
                      PopupMenuItem(
                        value: 'strich',
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        child: Text('Strich machen', style: TextStyle(fontSize: 16)),
                      ),
                      if (isCurrentUserWart) ...[
                        PopupMenuItem(
                          value: 'geld',
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          child: Text('Geld abziehen', style: TextStyle(fontSize: 16)),
                        ),
                        PopupMenuItem(
                          value: 'toggleWart',
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          child: Text(
                            isOtherWart ? 'Bierlistenwart entfernen' : 'Zum Bierlistenwart machen',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ];
                  }
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
