import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../skill.dart';
import '../skill_executor.dart';
import '../skill_result.dart';
// add_2_calendar transitively imports dart:io (web-incompatible), so it is
// reached only via this conditional-import seam.
import 'native_intent_calendar_stub.dart'
    if (dart.library.io) 'native_intent_calendar_io.dart'
    as calendar;

/// Runs a single whitelisted native intent given its already-decoded
/// [params] (the model-supplied `parameters` JSON). Parameters have already
/// been validated by [NativeIntentExecutor] before a handler is invoked.
typedef IntentHandler =
    Future<SkillResult> Function(Map<String, dynamic> params);

/// The native-intent [SkillExecutor] — the agent's bridge to the device for
/// `SkillType.intent` skills (Gallery's `run_intent`).
///
/// SECURITY MODEL (no foreign code, unlike JS skills):
///
/// 1. **Whitelist.** Only the six Gallery-parity intents in [_defaultHandlers]
///    can ever run — [send_email], [send_text], [create_calendar_event],
///    [read_calendar_events], [schedule_notification],
///    [get_current_date_and_time]. An unknown intent returns an [ErrorResult]
///    and NEVER reaches a handler.
/// 2. **Parameter validation.** Every intent's parameters are validated
///    (presence, type, email/phone/ISO-8601 shape, time-component ranges) by
///    [validateIntentParams] BEFORE any handler runs — a malformed call returns
///    an [ErrorResult], not a half-built action.
/// 3. **OS / user confirmation.** Outbound / destructive actions go through the
///    OS compose / confirm surface (`url_launcher` opens the system mail / SMS
///    composer; `add_2_calendar` opens the calendar's event editor). The model
///    proposes; the **user** is the one who presses send / save. Nothing fires
///    silently.
///
/// Handlers are injectable (the [handlers] constructor arg overrides specific
/// intents) so the plugins can be mocked in tests and the host app can provide
/// richer implementations (e.g. a real device-calendar reader) for intents the
/// built-in defaults only stub.
class NativeIntentExecutor extends SkillExecutor {
  /// Build the executor. [handlers], if given, override the built-in default
  /// handler for the matching intent name (everything else keeps its default).
  /// This is the seam tests use to inject fakes and apps use to extend.
  NativeIntentExecutor({Map<String, IntentHandler>? handlers})
    : _handlers = {..._defaultHandlers, ...?handlers};

  /// Intent names (Gallery parity). These are the ONLY actions that can run.
  static const String sendEmail = 'send_email';
  static const String sendText = 'send_text';
  static const String createCalendarEvent = 'create_calendar_event';
  static const String readCalendarEvents = 'read_calendar_events';
  static const String scheduleNotification = 'schedule_notification';
  static const String getCurrentDateAndTime = 'get_current_date_and_time';

  final Map<String, IntentHandler> _handlers;

  @override
  String get name => 'NativeIntentExecutor';

  /// Probes by [SkillType.intent]. The concrete intent name (e.g. `send_email`)
  /// is resolved at [execute] time from the skill name or the data payload, and
  /// checked against the whitelist there.
  @override
  bool canExecuteSkill(Skill skill) => skill.type == SkillType.intent;

  /// The whitelisted intent names this executor can run.
  Iterable<String> get whitelistedIntents => _handlers.keys;

  /// Whether [intent] is a whitelisted action.
  bool isWhitelisted(String intent) => _handlers.containsKey(intent);

  @override
  Future<SkillResult> execute(
    Skill skill,
    String dataJson, {
    String? secret,
  }) async {
    // The agent loop hands intents in as a synthetic Skill whose name is the
    // intent (set from the model's `intent` tool arg) and a `dataJson` that is
    // the model's `parameters` JSON. As a fallback (and for direct callers that
    // embed everything in one payload) we also accept a top-level `intent` key
    // inside the data payload.
    final parsed = _decodeObject(dataJson);
    if (parsed == null) {
      return ErrorResult(
        'Invalid parameters: expected a JSON object, got: $dataJson',
      );
    }

    var intent = skill.name.trim();
    var params = parsed;
    if (!isWhitelisted(intent)) {
      // Fall back to an `intent` field carried inside the data payload.
      final inner = parsed['intent'];
      if (inner is String && inner.trim().isNotEmpty) {
        intent = inner.trim();
        final innerParams = parsed['parameters'];
        if (innerParams is Map<String, dynamic>) {
          params = innerParams;
        } else if (innerParams is String) {
          final reparsed = _decodeObject(innerParams);
          if (reparsed != null) params = reparsed;
        }
      }
    }

    return _run(intent, params);
  }

  /// Run a whitelisted [intent] from an already-encoded [parametersJson]. The
  /// direct, plugin-free entry point used by unit tests and host code that has
  /// the intent name in hand (the agent loop goes through [execute]).
  Future<SkillResult> handleIntent(String intent, String parametersJson) async {
    final params = _decodeObject(parametersJson);
    if (params == null) {
      return ErrorResult(
        'Invalid parameters: expected a JSON object, got: $parametersJson',
      );
    }
    return _run(intent, params);
  }

  /// Whitelist check → parameter validation → handler dispatch.
  Future<SkillResult> _run(String intent, Map<String, dynamic> params) async {
    final handler = _handlers[intent];
    if (handler == null) {
      return ErrorResult(
        'Unknown intent "$intent". Allowed intents: '
        '${whitelistedIntents.join(', ')}.',
      );
    }

    final validationError = validateIntentParams(intent, params);
    if (validationError != null) {
      return ErrorResult('Invalid parameters for "$intent": $validationError');
    }

    try {
      return await handler(params);
    } catch (e) {
      return ErrorResult('Intent "$intent" failed: $e');
    }
  }

  /// The built-in handlers — one per whitelisted intent. Plugin-backed handlers
  /// guard their platform-specific calls; on an unsupported platform they
  /// return an [ErrorResult] rather than throw, so the model can recover and
  /// the package stays compile-clean on all six targets.
  static final Map<String, IntentHandler> _defaultHandlers = {
    sendEmail: _handleSendEmail,
    sendText: _handleSendText,
    createCalendarEvent: _handleCreateCalendarEvent,
    readCalendarEvents: _handleReadCalendarEvents,
    scheduleNotification: _handleScheduleNotification,
    getCurrentDateAndTime: _handleGetCurrentDateAndTime,
  };

  // --- default handlers -----------------------------------------------------

  /// `send_email` → opens the OS mail composer via a `mailto:` URI. The user
  /// reviews and presses send; nothing is sent silently.
  static Future<SkillResult> _handleSendEmail(
    Map<String, dynamic> params,
  ) async {
    final to = (params['extra_email'] as String).trim();
    final subject = (params['extra_subject'] as String?) ?? '';
    final body = (params['extra_text'] as String?) ?? '';
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      query: _encodeQuery({'subject': subject, 'body': body}),
    );
    return _launch(uri, 'mail composer');
  }

  /// `send_text` → opens the OS SMS composer via an `sms:` URI. The user
  /// reviews and presses send.
  static Future<SkillResult> _handleSendText(
    Map<String, dynamic> params,
  ) async {
    final phone = (params['phone_number'] as String).trim();
    final body = (params['sms_body'] as String?) ?? '';
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      query: _encodeQuery({'body': body}),
    );
    return _launch(uri, 'SMS composer');
  }

  /// `create_calendar_event` → opens the calendar's event editor. On Android /
  /// iOS via `add_2_calendar`; elsewhere via a Google Calendar template URL the
  /// browser opens. Either way the user confirms the save.
  static Future<SkillResult> _handleCreateCalendarEvent(
    Map<String, dynamic> params,
  ) async {
    final title = params['title'] as String;
    final description = (params['description'] as String?) ?? '';
    final begin = DateTime.parse(params['begin_time'] as String);
    final end = DateTime.parse(params['end_time'] as String);

    final isMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobile) {
      return calendar.addCalendarEvent(
        title: title,
        description: description,
        begin: begin,
        end: end,
      );
    }

    // Desktop / web fallback: Google Calendar event-template URL.
    final fmt = _googleCalendarStamp;
    final uri = Uri.parse(
      'https://calendar.google.com/calendar/render'
      '?action=TEMPLATE'
      '&text=${Uri.encodeQueryComponent(title)}'
      '&details=${Uri.encodeQueryComponent(description)}'
      '&dates=${fmt(begin)}/${fmt(end)}',
    );
    return _launch(uri, 'calendar');
  }

  /// `read_calendar_events` → reading the device calendar needs a
  /// platform-specific permissioned plugin that the cross-platform default does
  /// not bundle. Validates the date and returns a clear, recoverable error;
  /// host apps inject a real reader via the [handlers] constructor arg.
  static Future<SkillResult> _handleReadCalendarEvents(
    Map<String, dynamic> params,
  ) async {
    return ErrorResult(
      'Reading calendar events is not available with the built-in handler on '
      'this platform. Provide a custom "$readCalendarEvents" handler to '
      'NativeIntentExecutor to enable it. Requested date: ${params['date']}.',
    );
  }

  /// `schedule_notification` → schedules a local notification at the requested
  /// time via `flutter_local_notifications`. The OS shows it; nothing private
  /// leaves the device.
  static Future<SkillResult> _handleScheduleNotification(
    Map<String, dynamic> params,
  ) async {
    final title = params['title'] as String;
    final message = params['message'] as String;
    final hour = (params['hour'] as num).toInt();
    final minute = (params['minute'] as num).toInt();

    final when = _nextOccurrence(
      hour: hour,
      minute: minute,
      year: (params['year'] as num?)?.toInt(),
      month: (params['month'] as num?)?.toInt(),
      day: (params['day'] as num?)?.toInt(),
    );

    final plugin = fln.FlutterLocalNotificationsPlugin();
    tzdata.initializeTimeZones();
    final scheduled = tz.TZDateTime.from(when, tz.local);

    const details = fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        'agent_skill_tasks_channel',
        'Agent Skill Task',
        importance: fln.Importance.defaultImportance,
      ),
      iOS: fln.DarwinNotificationDetails(),
      macOS: fln.DarwinNotificationDetails(),
    );

    await plugin.zonedSchedule(
      id: (when.millisecondsSinceEpoch ~/ 1000) & 0x7fffffff,
      title: title,
      body: message,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
    );
    return TextResult(
      'Scheduled a notification "$title" for ${scheduled.toIso8601String()}.',
    );
  }

  /// `get_current_date_and_time` → pure Dart. No plugin, no platform branch.
  static Future<SkillResult> _handleGetCurrentDateAndTime(
    Map<String, dynamic> params,
  ) async {
    return TextResult(currentDateAndTime());
  }

  // --- helpers --------------------------------------------------------------

  /// Open [uri] in the OS, returning a [TextResult] on success or an
  /// [ErrorResult] when no app can handle it.
  static Future<SkillResult> _launch(Uri uri, String surface) async {
    if (!await launcher.canLaunchUrl(uri)) {
      return ErrorResult('No app available to open the $surface.');
    }
    final ok = await launcher.launchUrl(
      uri,
      mode: launcher.LaunchMode.externalApplication,
    );
    return ok
        ? TextResult('Opened the $surface for the user to confirm.')
        : ErrorResult('Could not open the $surface.');
  }

  /// `key=value&key=value` query with each value percent-encoded. Empty values
  /// are dropped so e.g. an empty SMS body produces a bare `sms:` URI.
  static String _encodeQuery(Map<String, String> params) {
    return params.entries
        .where((e) => e.value.isNotEmpty)
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}='
              '${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
  }

  /// `yyyyMMddTHHmmss` (local) for a Google Calendar template URL.
  static String _googleCalendarStamp(DateTime d) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${p(d.month)}${p(d.day)}T'
        '${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }

  /// The next [DateTime] matching the given time-of-day. If an explicit date
  /// ([year]/[month]/[day]) is supplied it is honoured; otherwise the next
  /// occurrence today-or-tomorrow is chosen so a past time rolls forward.
  static DateTime _nextOccurrence({
    required int hour,
    required int minute,
    int? year,
    int? month,
    int? day,
  }) {
    final now = DateTime.now();
    if (year != null && month != null && day != null) {
      return DateTime(year, month, day, hour, minute);
    }
    var when = DateTime(now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }
}

/// The current local date and time, formatted like Gallery's intent
/// (`yyyy-MM-ddTHH:mm:ss Weekday`). Pure Dart, exposed for direct/testable use.
String currentDateAndTime([DateTime? now]) {
  final d = now ?? DateTime.now();
  String p(int v) => v.toString().padLeft(2, '0');
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return '${d.year}-${p(d.month)}-${p(d.day)}T'
      '${p(d.hour)}:${p(d.minute)}:${p(d.second)} '
      '${weekdays[d.weekday - 1]}';
}

/// Validate the [params] for [intent]. Returns null when valid, otherwise a
/// human-readable reason. Pure (no I/O, no plugins) so it is fully unit-testable
/// and runs BEFORE any action is taken. An unknown [intent] is reported as such.
String? validateIntentParams(String intent, Map<String, dynamic> params) {
  switch (intent) {
    case NativeIntentExecutor.sendEmail:
      final email = params['extra_email'];
      if (email is! String || email.trim().isEmpty) {
        return 'missing required string "extra_email".';
      }
      if (!_isValidEmail(email.trim())) {
        return 'invalid email address "$email".';
      }
      return _ensureOptionalStrings(params, ['extra_subject', 'extra_text']);

    case NativeIntentExecutor.sendText:
      final phone = params['phone_number'];
      if (phone is! String || phone.trim().isEmpty) {
        return 'missing required string "phone_number".';
      }
      if (!_isValidPhone(phone.trim())) {
        return 'invalid phone number "$phone".';
      }
      return _ensureOptionalStrings(params, ['sms_body']);

    case NativeIntentExecutor.createCalendarEvent:
      final missing = _requireStrings(params, [
        'title',
        'begin_time',
        'end_time',
      ]);
      if (missing != null) return missing;
      final begin = DateTime.tryParse(params['begin_time'] as String);
      if (begin == null) {
        return 'begin_time "${params['begin_time']}" is not an ISO-8601 '
            'date-time.';
      }
      final end = DateTime.tryParse(params['end_time'] as String);
      if (end == null) {
        return 'end_time "${params['end_time']}" is not an ISO-8601 date-time.';
      }
      if (!end.isAfter(begin)) {
        return 'end_time must be after begin_time.';
      }
      return _ensureOptionalStrings(params, ['description']);

    case NativeIntentExecutor.readCalendarEvents:
      final date = params['date'];
      if (date is! String || date.trim().isEmpty) {
        return 'missing required string "date".';
      }
      if (DateTime.tryParse(date.trim()) == null) {
        return 'date "$date" is not an ISO-8601 date.';
      }
      return null;

    case NativeIntentExecutor.scheduleNotification:
      final missing = _requireStrings(params, ['title', 'message']);
      if (missing != null) return missing;
      final hourError = _requireIntInRange(params, 'hour', 0, 23);
      if (hourError != null) return hourError;
      final minuteError = _requireIntInRange(params, 'minute', 0, 59);
      if (minuteError != null) return minuteError;
      // Optional explicit date — if any component is present, validate it.
      if (params.containsKey('year') ||
          params.containsKey('month') ||
          params.containsKey('day')) {
        final monthError = _optionalIntInRange(params, 'month', 1, 12);
        if (monthError != null) return monthError;
        final dayError = _optionalIntInRange(params, 'day', 1, 31);
        if (dayError != null) return dayError;
        final yearError = _optionalIntInRange(params, 'year', 1970, 9999);
        if (yearError != null) return yearError;
      }
      return null;

    case NativeIntentExecutor.getCurrentDateAndTime:
      // No parameters required.
      return null;

    default:
      return 'unknown intent.';
  }
}

/// A pragmatic email shape check (not RFC-5322 exhaustive): one `@`, a
/// non-empty local part, and a dotted domain with no whitespace.
bool _isValidEmail(String value) {
  final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  return re.hasMatch(value);
}

/// A lenient phone check: optional leading `+`, then 7–15 digits, allowing
/// spaces / dashes / parens as separators.
bool _isValidPhone(String value) {
  final digits = value.replaceAll(RegExp(r'[\s\-()]'), '');
  return RegExp(r'^\+?\d{7,15}$').hasMatch(digits);
}

/// Ensure every key in [required] is a non-empty string. Returns null if all
/// present, else a reason naming the first offender.
String? _requireStrings(Map<String, dynamic> params, List<String> required) {
  for (final key in required) {
    final v = params[key];
    if (v is! String || v.trim().isEmpty) {
      return 'missing required string "$key".';
    }
  }
  return null;
}

/// Ensure any present key in [optional] is a string (when supplied). Returns
/// null if all present-or-absent values are strings.
String? _ensureOptionalStrings(
  Map<String, dynamic> params,
  List<String> optional,
) {
  for (final key in optional) {
    if (params.containsKey(key) && params[key] is! String) {
      return 'optional field "$key" must be a string when provided.';
    }
  }
  return null;
}

/// Require an integer-valued key in `[min, max]`.
String? _requireIntInRange(
  Map<String, dynamic> params,
  String key,
  int min,
  int max,
) {
  final v = params[key];
  if (v is! num || v != v.toInt()) {
    return 'missing or non-integer "$key".';
  }
  final i = v.toInt();
  if (i < min || i > max) {
    return '"$key" must be between $min and $max (got $i).';
  }
  return null;
}

/// Like [_requireIntInRange] but the key is optional; absent → ok.
String? _optionalIntInRange(
  Map<String, dynamic> params,
  String key,
  int min,
  int max,
) {
  if (!params.containsKey(key) || params[key] == null) return null;
  return _requireIntInRange(params, key, min, max);
}

/// Decode [json] into a `Map<String, dynamic>`, returning null on any failure
/// (non-JSON, or a non-object top level). An empty string decodes to an empty
/// map so a no-parameter intent works without an explicit `{}`.
Map<String, dynamic>? _decodeObject(String json) {
  final trimmed = json.trim();
  if (trimmed.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
