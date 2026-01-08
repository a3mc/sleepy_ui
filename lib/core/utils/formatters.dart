import 'package:intl/intl.dart';

// Number formatting utilities
class NumberFormatter {
  static final _numberFormat = NumberFormat('#,###');
  static final _decimalFormat = NumberFormat('#,##0.00');

  static String formatInt(int number) {
    return _numberFormat.format(number);
  }

  static String formatDouble(double number, {int decimals = 2}) {
    return _decimalFormat.format(number);
  }

  static String formatCredits(int credits) {
    if (credits >= 1000000) {
      return '${(credits / 1000000).toStringAsFixed(2)}M';
    } else if (credits >= 1000) {
      return '${(credits / 1000).toStringAsFixed(1)}K';
    }
    return credits.toString();
  }

  static String formatDelta(int delta) {
    if (delta > 0) {
      return '+${formatInt(delta)}';
    }
    return formatInt(delta);
  }
}

// Date/time formatting utilities
class DateFormatter {
  static final _timeFormat = DateFormat('HH:mm:ss');
  static final _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  static String formatTime(DateTime dateTime) {
    return _timeFormat.format(dateTime);
  }

  static String formatDateTime(DateTime dateTime) {
    return _dateTimeFormat.format(dateTime);
  }

  static String formatRelative(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 5) {
      return 'just now';
    } else if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
