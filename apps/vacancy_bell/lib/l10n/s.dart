import '../core/json_read.dart';
import '../core/ymd.dart';
import '../logic/calendar.dart';
import '../logic/report.dart';
import '../models/profile.dart';
import '../models/taxonomy.dart';
import 'strings.dart';

/// Strings and formatting for one language.
class S {
  const S(this.lang);
  final AppLang lang;

  static const en = S(AppLang.en);
  static const hi = S(AppLang.hi);

  static S of(AppLang lang) => lang == AppLang.hi ? hi : en;

  String t(L key, [Map<String, Object?> args = const {}]) {
    final template = stringsFor(lang)[key] ?? stringsEn[key] ?? key.name;
    return args.isEmpty ? template : fillTemplate(template, args);
  }

  String text(LocalText? v) => v?.of(lang) ?? '';

  static const _monthsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _monthsHi = [
    'जन॰', 'फ़र॰', 'मार्च', 'अप्रैल', 'मई', 'जून', //
    'जुलाई', 'अग॰', 'सित॰', 'अक्टू॰', 'नव॰', 'दिस॰',
  ];
  static const _monthsLongEn = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthsLongHi = [
    'जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून', //
    'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर',
  ];
  static const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekdaysHi = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'];

  /// "05 Nov 2026".
  String date(Ymd d) {
    final m = (lang == AppLang.hi ? _monthsHi : _monthsEn)[d.month - 1];
    return '${d.day.toString().padLeft(2, '0')} $m ${d.year}';
  }

  /// "November 2026".
  String monthYear(int year, int month) =>
      '${(lang == AppLang.hi ? _monthsLongHi : _monthsLongEn)[month - 1]} $year';

  String weekday(Ymd d) =>
      (lang == AppLang.hi ? _weekdaysHi : _weekdaysEn)[d.weekday - 1];

  /// "09:00" (24-hour, as used in India time notes).
  String time(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// A UTC instant shown in India time: "07 Oct 2026, 14:30".
  String instantIst(DateTime t) {
    final ist = t.toUtc().add(istOffset);
    return '${date(Ymd.ofDateTime(ist))}, ${time(ist.hour, ist.minute)}';
  }

  /// "2 h ago" style text for [t] relative to [now].
  String ago(DateTime at, DateTime now) {
    final d = now.difference(at);
    if (d.inMinutes < 1) return t(L.justNow);
    if (d.inHours < 1) return t(L.minutesAgo, {'n': d.inMinutes});
    if (d.inDays < 1) return t(L.hoursAgo, {'n': d.inHours});
    return t(L.daysAgo, {'n': d.inDays});
  }

  /// Indian digit grouping: 1234567 -> "12,34,567".
  static String number(int n) {
    final neg = n < 0;
    final s = n.abs().toString();
    if (s.length <= 3) return neg ? '-$s' : s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${neg ? '-' : ''}${parts.join(',')},$last3';
  }

  String rupees(int n) => '₹${number(n)}';

  String postType(PostType t) => this.t(switch (t) {
        PostType.job => L.tabJobs,
        PostType.admitCard => L.tabAdmitCard,
        PostType.result => L.tabResult,
        PostType.answerKey => L.tabAnswerKey,
        PostType.syllabus => L.tabSyllabus,
        PostType.admission => L.tabAdmission,
        PostType.notice => L.tabNotice,
      });

  String category(JobCategory c) => t(switch (c) {
        JobCategory.ssc => L.jcSsc,
        JobCategory.railway => L.jcRailway,
        JobCategory.banking => L.jcBanking,
        JobCategory.upsc => L.jcUpsc,
        JobCategory.defence => L.jcDefence,
        JobCategory.police => L.jcPolice,
        JobCategory.teaching => L.jcTeaching,
        JobCategory.statePsc => L.jcStatePsc,
        JobCategory.psu => L.jcPsu,
        JobCategory.medical => L.jcMedical,
        JobCategory.engineering => L.jcEngineering,
        JobCategory.other => L.jcOther,
      });

  String qualification(Qualification q) => t(switch (q) {
        Qualification.class8 => L.qual8th,
        Qualification.class10 => L.qual10th,
        Qualification.class12 => L.qual12th,
        Qualification.iti => L.qualIti,
        Qualification.diploma => L.qualDiploma,
        Qualification.graduate => L.qualGraduate,
        Qualification.engineering => L.qualEngineering,
        Qualification.medical => L.qualMedical,
        Qualification.law => L.qualLaw,
        Qualification.postgraduate => L.qualPostgraduate,
        Qualification.any => L.qualAny,
      });

  String socialCategory(SocialCategory c) => t(switch (c) {
        SocialCategory.general => L.catGeneral,
        SocialCategory.obc => L.catObc,
        SocialCategory.sc => L.catSc,
        SocialCategory.st => L.catSt,
        SocialCategory.ews => L.catEws,
      });

  String gender(Gender g) => t(switch (g) {
        Gender.male => L.genderMale,
        Gender.female => L.genderFemale,
        Gender.other => L.genderOther,
      });

  String reportReason(ReportReason r) => t(switch (r) {
        ReportReason.wrongDate => L.reasonWrongDate,
        ReportReason.wrongFee => L.reasonWrongFee,
        ReportReason.wrongEligibility => L.reasonWrongEligibility,
        ReportReason.brokenLink => L.reasonBrokenLink,
        ReportReason.other => L.reasonOther,
      });

  String calendarKind(CalendarKind k) => t(switch (k) {
        CalendarKind.lastDate => L.calLastDate,
        CalendarKind.exam => L.calExam,
        CalendarKind.admitCard => L.calAdmitCard,
        CalendarKind.result => L.calResult,
        CalendarKind.other => L.importantDates,
      });

  String state(String code) {
    if (code == allStates) return t(L.allStates);
    return stateByCode[code]?.name(lang) ?? code;
  }

  /// "18 to 32 years", "Up to 30 years", or null when both are unknown.
  String? ageRange(int? min, int? max) {
    if (min != null && max != null) return t(L.ageRange, {'min': min, 'max': max});
    if (min != null) return t(L.ageMinOnly, {'min': min});
    if (max != null) return t(L.ageMaxOnly, {'max': max});
    return null;
  }

  String languageName(AppLang l) => l == AppLang.hi ? 'हिंदी' : 'English';
}
