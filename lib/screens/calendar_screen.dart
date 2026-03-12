import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class CalendarScreen extends StatefulWidget {
  final String employeeId;
  const CalendarScreen({super.key, required this.employeeId});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _currentMonth = DateTime.now();
  Map<String, dynamic> _attendanceData = {};
  bool _isLoading = true;
  int _presentDays = 0;
  int _absentDays = 0;
  int _lateDays = 0;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);

    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

    final response = await Supabase.instance.client
        .from('attendance_records')
        .select()
        .eq('employee_id', widget.employeeId)
        .gte('date', DateFormat('yyyy-MM-dd').format(firstDay))
        .lte('date', DateFormat('yyyy-MM-dd').format(lastDay));

    final Map<String, dynamic> data = {};
    int present = 0, absent = 0, late = 0;

    for (final record in response) {
      data[record['date']] = record;
      if (record['status'] == 'present') present++;
      if (record['status'] == 'absent') absent++;
      if (record['late_minutes'] > 0) late++;
    }

    setState(() {
      _attendanceData = data;
      _presentDays = present;
      _absentDays = absent;
      _lateDays = late;
      _isLoading = false;
    });
  }

  Color _getDayColor(String date) {
    if (!_attendanceData.containsKey(date)) return Colors.grey[300]!;
    final record = _attendanceData[date];
    final status = record['status'];
    if (status == 'present') {
      if (record['late_minutes'] > 0) return Colors.orange;
      return Colors.green;
    }
    if (status == 'absent') return Colors.red;
    if (status == 'leave') return Colors.blue;
    return Colors.grey[300]!;
  }

  void _showDayDetails(String date) {
    if (!_attendanceData.containsKey(date)) return;
    final record = _attendanceData[date];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('dd MMMM yyyy').format(DateTime.parse(date)),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            _detailRow('Status', record['status']?.toUpperCase() ?? 'N/A'),
            _detailRow(
              'Duty In',
              record['duty_in'] != null
                  ? DateFormat('hh:mm a').format(
                      DateTime.parse(record['duty_in']).toLocal())
                  : '--:--',
            ),
            _detailRow(
              'Duty Out',
              record['duty_out'] != null
                  ? DateFormat('hh:mm a').format(
                      DateTime.parse(record['duty_out']).toLocal())
                  : '--:--',
            ),
            _detailRow(
              'Working Hours',
              '${(record['working_minutes'] ~/ 60)}h ${record['working_minutes'] % 60}m',
            ),
            _detailRow(
              'Late',
              '${record['late_minutes']} mins',
            ),
            _detailRow(
              'Overtime',
              '${record['overtime_minutes']} mins',
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final firstWeekday = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    ).weekday % 7;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Month Navigation
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _currentMonth = DateTime(
                              _currentMonth.year,
                              _currentMonth.month - 1,
                            );
                          });
                          _loadAttendance();
                        },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        DateFormat('MMMM yyyy').format(_currentMonth),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _currentMonth = DateTime(
                              _currentMonth.year,
                              _currentMonth.month + 1,
                            );
                          });
                          _loadAttendance();
                        },
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),

                  // Summary Cards
                  Row(
                    children: [
                      _summaryCard('Present', _presentDays, Colors.green),
                      _summaryCard('Absent', _absentDays, Colors.red),
                      _summaryCard('Late', _lateDays, Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Calendar
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Day headers
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                              .map((d) => SizedBox(
                                    width: 36,
                                    child: Text(
                                      d,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 8),

                        // Calendar Grid
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            childAspectRatio: 1,
                          ),
                          itemCount: firstWeekday + daysInMonth,
                          itemBuilder: (context, index) {
                            if (index < firstWeekday) {
                              return const SizedBox();
                            }
                            final day = index - firstWeekday + 1;
                            final date = DateFormat('yyyy-MM-dd').format(
                              DateTime(
                                _currentMonth.year,
                                _currentMonth.month,
                                day,
                              ),
                            );
                            final color = _getDayColor(date);
                            final isToday = day == DateTime.now().day &&
                                _currentMonth.month == DateTime.now().month &&
                                _currentMonth.year == DateTime.now().year;

                            return GestureDetector(
                              onTap: () => _showDayDetails(date),
                              child: Container(
                                margin: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isToday
                                      ? Border.all(
                                          color: Colors.blue,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '$day',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: color == Colors.grey[300]
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Legend
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _legendItem('Present', Colors.green),
                        _legendItem('Absent', Colors.red),
                        _legendItem('Late', Colors.orange),
                        _legendItem('Leave', Colors.blue),
                        _legendItem('Weekend', Colors.grey),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}
