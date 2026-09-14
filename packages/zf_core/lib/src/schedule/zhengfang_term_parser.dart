import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'academic_term.dart';
import 'schedule_parse_exception.dart';

TermCatalog parseZhengfangTermCatalog(String source) {
  final document = html.parse(source);
  final year = _field(document, const {'xnm', 'xnd', 'ddlxn', 'xn'});
  final term = _field(document, const {'xqm', 'xqd', 'ddlxq', 'xq'});
  final pairedOptions = document
      .querySelectorAll('option[data-xnm][data-xqm]')
      .where((element) => !_disabled(element));
  final paired = <AcademicTerm>[];
  AcademicTerm? selectedPair;
  for (final option in pairedOptions) {
    final yearCode = option.attributes['data-xnm']!;
    final termCode = option.attributes['data-xqm']!;
    if (yearCode.trim().isEmpty || termCode.trim().isEmpty) continue;
    final value = AcademicTerm(
      yearCode: yearCode,
      termCode: termCode,
      label: option.text.trim().isEmpty
          ? '$yearCode / $termCode'
          : option.text.trim(),
    );
    paired.add(value);
    if (option.attributes.containsKey('selected')) selectedPair = value;
  }
  if ((year == null || term == null) && paired.isEmpty) {
    throw const ScheduleParseException(
      ScheduleParseCode.missingField,
      '学校页面未提供可识别的学年、学期选项',
      field: 'xnm/xqm',
    );
  }
  final yearOptions = year == null ? <TermOption>[] : _options(year);
  final termOptions = term == null ? <TermOption>[] : _options(term);
  final selectedYear = year == null ? null : _selected(year);
  final selectedPart = term == null ? null : _selected(term);
  final selected = selectedYear == null || selectedPart == null
      ? selectedPair
      : AcademicTerm(
          yearCode: selectedYear.code,
          termCode: selectedPart.code,
          label: '${selectedYear.label} ${selectedPart.label}',
        );
  final known = <String, AcademicTerm>{
    for (final value in paired) value.key: value,
  };
  if (selected != null) known[selected.key] = selected;
  return TermCatalog(
    terms: known.values.toList(),
    selectedTerm: selected,
    yearOptions: yearOptions,
    termOptions: termOptions,
  );
}

Element? _field(Document document, Set<String> names) {
  for (final tag in const ['select', 'input']) {
    for (final element in document.querySelectorAll(tag)) {
      if (_disabled(element)) continue;
      final name = (element.attributes['name'] ?? element.id)
          .split(r'$')
          .last
          .toLowerCase();
      if (names.contains(name)) return element;
    }
  }
  return null;
}

List<TermOption> _options(Element field) {
  if (field.localName == 'input') {
    final value = _option(field);
    return value == null ? [] : [value];
  }
  final options = <String, TermOption>{};
  for (final element in field.querySelectorAll('option')) {
    final value = _option(element);
    if (value != null) options[value.code] = value;
  }
  return options.values.toList();
}

TermOption? _selected(Element field) {
  if (field.localName == 'input') return _option(field);
  final options = field.querySelectorAll('option');
  final explicit = options.where(
    (option) => option.attributes.containsKey('selected'),
  );
  if (explicit.length > 1) {
    throw const ScheduleParseException(
      ScheduleParseCode.invalidValue,
      '学校的学期选择器同时选中了多个值',
      field: 'xnm/xqm',
    );
  }
  final selected =
      explicit.firstOrNull ??
      options.where((option) => !_disabled(option)).firstOrNull;
  return selected == null ? null : _option(selected);
}

TermOption? _option(Element element) {
  if (_disabled(element)) return null;
  final value = element.attributes['value'];
  if (value == null || value.trim().isEmpty) return null;
  final text = element.localName == 'input'
      ? element.attributes['data-label'] ?? value
      : element.text.trim();
  if (RegExp(r'^(全部|所有|请选择)(?:$|学年|学期)').hasMatch(text)) return null;
  return TermOption(code: value, label: text.isEmpty ? value : text);
}

bool _disabled(Element element) {
  for (Element? current = element; current != null; current = current.parent) {
    if (current.attributes.containsKey('disabled')) return true;
  }
  return false;
}
