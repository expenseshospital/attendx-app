import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'calendar_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> employeeData;
  const HomeScreen({super.key, required this.employeeData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  bool _isInsideGeofence = false;
  bool _isDutyOn = false;
  bool _isLoading = false;
  String _dutyInTime = '';
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _checkLocation();
    _checkTodayAttendance();
  }

  Future<void> _checkLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    Position position = await Geolocator.getCurrentPosition();
    setState(() => _currentPosition = position);
    _checkGeofence(position);
  }

  void _checkGeofence(Position position) {
    // Get org location from employee data
    final orgLat = widget.employeeData['org_lat'] ?? 0.0;
    final orgLng = widget.employeeData['org_lng'] ?? 0.0;
    final radius = widget.employeeData['geofence_radius'] ?? 100;

    double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      orgLat,
      orgLng,
    );

    setState(() {
      _isInsideGeofence = distance <= radius;
    });
  }

  Future<void> _checkTodayAttendance() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final response = await Supabase.instance.client
        .from('attendance_records')
        .select()
        .eq('employee_id', widget.employeeData['id'])
        .eq('date', today)
        .maybeSingle();

    if (response != null) {
      setState(() {
        _isDutyOn = response['duty_in'] != null && 
                    response['duty_out'] == null;
        if (response['duty_in'] != null) {
          _dutyInTime = DateFormat('hh:mm a').format(
            DateTime.parse(response['duty_in']).toLocal(),
          );
        }
      });
    }
  }

  Future<void> _markDutyIn() async {
    if (!_isInsideGeofence) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are outside office location!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateTime.now().toUtc().toIso8601String();

    await Supabase.instance.client
        .from('attendance_records')
        .insert({
          'employee_id': widget.employeeData['id'],
          'org_id': widget.employeeData['org_id'],
          'date': today,
          'duty_in': now,
          'in_lat': _currentPosition?.latitude,
          'in_lng': _currentPosition?.longitude,
          'status': 'present',
        });

    setState(() {
      _isDutyOn = true;
      _dutyInTime = DateFormat('hh:mm a').format(DateTime.now());
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Duty IN marked successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _markDutyOut() async {
    setState(() => _isLoading = true);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateTime.now().toUtc().toIso8601String();

    await Supabase.instance.client
        .from('attendance_records')
        .update({
          'duty_out': now,
          'out_lat': _currentPosition?.latitude,
          'out_lng': _currentPosition?.longitude,
        })
        .eq('employee_id', widget.employeeData['id'])
        .eq('date', today);

    setState(() {
      _isDutyOn = false;
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Duty OUT marked successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D6FE8),
        title: const Text(
          'AttendX',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: _isInsideGeofence ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  _isInsideGeofence ? 'Inside' : 'Outside',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildHomeTab(),
          CalendarScreen(employeeId: widget.employeeData['id']),
          ProfileScreen(employeeData: widget.employeeData),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        selectedItemColor: const Color(0xFF1D6FE8),
        onTap: (index) => setState(() => _currentTab = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.access_time),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Welcome Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1D6FE8), Color(0xFF0A4FB4)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good ${_getGreeting()}!',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                Text(
                  widget.employeeData['name'] ?? 'Employee',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat('EEEE, dd MMM yyyy').format(DateTime.now()),
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Geofence Status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isInsideGeofence
                  ? Colors.green[50]
                  : Colors.red[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isInsideGeofence ? Colors.green : Colors.red,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isInsideGeofence
                      ? Icons.location_on
                      : Icons.location_off,
                  color: _isInsideGeofence ? Colors.green : Colors.red,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isInsideGeofence
                          ? 'Inside Office Zone'
                          : 'Outside Office Zone',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isInsideGeofence
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    Text(
                      _isInsideGeofence
                          ? 'You can mark attendance'
                          : 'Move to office to mark attendance',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: _checkLocation,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Duty Time Card
          if (_dutyInTime.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Duty In',
                          style: TextStyle(color: Colors.grey)),
                      Text(
                        _dutyInTime,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Duty Out',
                          style: TextStyle(color: Colors.grey)),
                      Text(
                        _isDutyOn ? '--:--' : 'Done',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _isDutyOn ? Colors.grey : Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 30),

          // Duty IN/OUT Button
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : (_isDutyOn ? _markDutyOut : _markDutyIn),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isDutyOn ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      _isDutyOn ? 'DUTY OUT' : 'DUTY IN',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }
}
