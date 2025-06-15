import 'package:flutter/services.dart';
import 'dart:math' as math;

class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    final oldCursor = oldValue.selection.baseOffset;
    final newCursor = newValue.selection.baseOffset;
    final isDeleting = newText.length < oldText.length;

    // Nur Ziffern und Komma behalten
    final cleanOld = oldText.replaceAll(RegExp(r'[^0-9,]'), '');
    final cleanNew = newText.replaceAll(RegExp(r'[^0-9,]'), '');

    // Unterschied der rohen Eingabe vs. des "gereinigten" Strings
    final rawDelta = newText.length - oldText.length;
    final cleanDelta = cleanNew.length - cleanOld.length;

    // Position des Kommas im alten, "gereinigten" Text
    final oldComma = cleanOld.indexOf(',');

    // === 0) Ungültige Eingabe hinter dem Komma komplett ignorieren ===
    // Wenn im rohen Text etwas hinzugekommen ist, im gereinigten aber nichts
    // UND der Cursor hinter dem Komma stand, verwerfen wir komplett.
    if (!isDeleting && rawDelta > 0 && cleanDelta == 0 && oldComma >= 0 && oldCursor > oldComma) {
      return oldValue;
    }

    // Vor- und Nachkommateil im alten Text
    final oldBefore = (oldComma >= 0)
        ? cleanOld.substring(0, oldComma)
        : cleanOld;
    final rawOldAfter = (oldComma >= 0)
        ? cleanOld.substring(oldComma + 1)
        : '';
    // Genau 2 Dezimalstellen vorhalten
    final oldAfter = rawOldAfter
        .padRight(2, '0')
        .substring(0, 2)
        .split('');

    // Hilfsfunktion zum Zusammenbauen von Text und Cursor
    TextEditingValue finish(String before, String after, int cursorPos) {
      if (after.isEmpty) {
        return TextEditingValue(
          text: before,
          selection: TextSelection.collapsed(offset: cursorPos),
        );
      } else {
        final merged = '$before,$after';
        return TextEditingValue(
          text: merged,
          selection: TextSelection.collapsed(offset: cursorPos),
        );
      }
    }

    // === 1) Löschen (Backspace) ===
    if (isDeleting) {
      final target = oldCursor - 1;

      // 1a) In Dezimalstellen löschen?
      if (oldComma >= 0 && target > oldComma) {
        final decIdx = target - oldComma - 1; // 0 oder 1
        if (decIdx == 0 || decIdx == 1) {
          oldAfter[decIdx] = '0';
          return finish(oldBefore, oldAfter.join(), oldComma + 1 + decIdx);
        }
      }

      // 1b) Komma löschen?
      if (oldComma >= 0 && target == oldComma) {
        return finish(oldBefore, '', oldBefore.length);
      }

      // 1c) Im Integer-Bereich löschen
      if (target >= 0 && target < oldBefore.length) {
        final newBefore = oldBefore.substring(0, target) +
            oldBefore.substring(target + 1);
        if (oldComma >= 0) {
          return finish(newBefore, oldAfter.join(), target);
        } else {
          return finish(newBefore, '', target);
        }
      }

      // Fallback: safe state
      return finish(oldBefore, oldAfter.join(), oldBefore.length);
    }

    // === 2) Einfügen ===
    // Anzahl eingefügter Zeichen im gereinigten Text
    final insCount = cleanDelta > 0 ? cleanDelta : 0;
    final insPos = oldCursor;
    final inserted = (insCount > 0 && insPos + insCount <= cleanNew.length)
        ? cleanNew.substring(insPos, insPos + insCount)
        : '';

    // 2a) Doppeltes Komma ignorieren
    if (oldComma >= 0 && inserted.contains(',')) {
      return oldValue;
    }
    // 2b) Frisches Komma (erstes) → sofort ",00" anfügen
    if (oldComma < 0 && inserted.contains(',')) {
      final before = cleanNew.split(',')[0];
      return finish(before, '00', before.length + 1);
    }
    // 2c) Einfügen vor oder auf dem Komma → Integer-Bereich
    if (insPos <= oldBefore.length && !inserted.contains(',')) {
      final before = StringBuffer()
        ..write(oldBefore.substring(0, insPos))
        ..write(inserted)
        ..write(oldBefore.substring(insPos));
      return finish(
        before.toString(),
        (oldComma >= 0) ? oldAfter.join() : '',
        insPos + inserted.length,
      );
    }
    // 2d) Erste Dezimalstelle ersetzen
    if (oldComma >= 0 &&
        insPos == oldComma + 1 &&
        RegExp(r'^\d$').hasMatch(inserted)) {
      oldAfter[0] = inserted;
      return finish(oldBefore, oldAfter.join(), oldComma + 2);
    }
    // 2e) Zweite Dezimalstelle ersetzen
    if (oldComma >= 0 &&
        insPos == oldComma + 2 &&
        RegExp(r'^\d$').hasMatch(inserted)) {
      oldAfter[1] = inserted;
      return finish(oldBefore, oldAfter.join(), oldComma + 3);
    }
    // 2f) Alles hinter der zweiten Dezimalstelle ignorieren
    if (oldComma >= 0 && insPos >= oldComma + 3) {
      return oldValue;
    }

    // 2g) Fallback: kompletten String neu padden/kürzen
    final parts = cleanNew.split(',');
    final before = parts[0];
    var after = (parts.length > 1) ? parts[1] : '';
    if (after.length < 2) {
      after = after.padRight(2, '0');
    } else if (after.length > 2) {
      after = after.substring(0, 2);
    }
    final commaPos = before.length;
    final outCursor = (newCursor <= commaPos)
        ? newCursor
        : math.min(newCursor, before.length + 1 + after.length);
    return finish(before, after, outCursor);
  }
}
