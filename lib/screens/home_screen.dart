import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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
  String _dutyOutTime = '';
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

  void _checkGeofence(Position position) async {
    try {
      final orgData = await Supabase.instance.client
          .from('organizations')
          .select('lat, lng, geofence_radius')
          .eq('id', widget.employeeData['org_id'])
          .single();
      final orgLat = (orgData['lat'] ?? 0.0) as double;
      final orgLng = (orgData['lng'] ?? 0.0) as double;
      final radius = (orgData['geofence_radius'] ?? 100) as num;
    double distance = Geolocator.distanceBetween(
      position.latitude, position.longitude, orgLat, orgLng,
    );
    setState(() => _isInsideGeofence = distance <= radius);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Distance: ${distance.toStringAsFixed(0)}m, Radius: $radius, Inside: ${distance <= radius}'),
      duration: const Duration(seconds: 5),
    ));
    } catch (e) {
      setState(() => _isInsideGeofence = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Geofence error: $e'),
        duration: const Duration(seconds: 5),
      ));
    }
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
        _isDutyOn = response['duty_in'] != null && response['duty_out'] == null;
        if (response['duty_in'] != null) {
          _dutyInTime = DateFormat('hh:mm a').format(DateTime.parse(response['duty_in']).toLocal());
        }
        if (response['duty_out'] != null) {
          _dutyOutTime = DateFormat('hh:mm a').format(DateTime.parse(response['duty_out']).toLocal());
        }
      });
    }
  }

  Future<bool> _verifyFace() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    bool faceDetected = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => FaceVerificationDialog(
        camera: frontCamera,
        onVerified: (result) {
          faceDetected = result;
          Navigator.pop(context);
        },
      ),
    );
    return faceDetected;
  }

  Future<void> _markDutyIn() async {
    if (!_isInsideGeofence) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You are outside office location!'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Please verify your face...'),
      backgroundColor: Colors.blue,
      duration: Duration(seconds: 2),
    ));
    bool faceOk = await _verifyFace();
    if (!faceOk) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Face not detected! Please try again.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateTime.now().toUtc().toIso8601String();
    await Supabase.instance.client.from('attendance_records').insert({
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
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Duty IN marked!'), backgroundColor: Colors.green,
    ));
  }

  Future<void> _markDutyOut() async {
    setState(() => _isLoading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Please verify your face...'),
      backgroundColor: Colors.blue,
      duration: Duration(seconds: 2),
    ));
    bool faceOk = await _verifyFace();
    if (!faceOk) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Face not detected! Please try again.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateTime.now().toUtc().toIso8601String();
    await Supabase.instance.client.from('attendance_records').update({
      'duty_out': now,
      'out_lat': _currentPosition?.latitude,
      'out_lng': _currentPosition?.longitude,
    }).eq('employee_id', widget.employeeData['id']).eq('date', today);
    setState(() {
      _isDutyOn = false;
      _dutyOutTime = DateFormat('hh:mm a').format(DateTime.now());
      _isLoading = false;
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Duty OUT marked!'), backgroundColor: Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D6FE8),
        elevation: 0,
        title: const Text('AttendX', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              Icon(Icons.circle, size: 12, color: _isInsideGeofence ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 4),
              Text(_isInsideGeofence ? 'Inside' : 'Outside', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
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
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        elevation: 10,
        onTap: (index) => setState(() => _currentTab = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.access_time), label: 'Attendance'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Calendar'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Greeting Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D6FE8), Color(0xFF0A4FB4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white.withOpacity(0.2),
              child: Text(
                (widget.employeeData['name'] ?? 'E')[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Good ${_getGreeting()}!', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              Text(widget.employeeData['name'] ?? 'Employee',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(DateFormat('EEEE, dd MMM yyyy').format(DateTime.now()),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // Time Cards Row
        Row(children: [
          Expanded(child: _buildTimeCard('Duty IN', _dutyInTime.isEmpty ? '--:--' : _dutyInTime, Icons.login, Colors.green)),
          const SizedBox(width: 12),
          Expanded(child: _buildTimeCard('Duty OUT', _dutyOutTime.isEmpty ? '--:--' : _dutyOutTime, Icons.logout, Colors.red)),
        ]),
        const SizedBox(height: 16),

        // Location Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            border: Border.all(color: _isInsideGeofence ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isInsideGeofence ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_isInsideGeofence ? Icons.location_on : Icons.location_off,
                color: _isInsideGeofence ? Colors.green : Colors.red, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_isInsideGeofence ? 'Inside Office Zone' : 'Outside Office Zone',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                  color: _isInsideGeofence ? Colors.green[700] : Colors.red[700])),
              Text(_isInsideGeofence ? 'You can mark attendance' : 'Move to office to mark attendance',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ])),
            IconButton(
              onPressed: _checkLocation,
              icon: const Icon(Icons.refresh, color: Color(0xFF1D6FE8)),
            ),
          ]),
        ),
        const SizedBox(height: 24),

        // Face Registration Notice
        if (widget.employeeData['face_registered'] == false)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Please register your face in Profile tab first!',
                style: TextStyle(fontSize: 12, color: Colors.orange))),
              TextButton(
                onPressed: () => setState(() => _currentTab = 2),
                child: const Text('Go', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.face, color: Color(0xFF1D6FE8), size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('Face verification required for attendance',
                style: TextStyle(fontSize: 12, color: Color(0xFF1D6FE8)))),
            ]),
          ),
        const SizedBox(height: 24),

        // DUTY Button
        SizedBox(
          width: double.infinity,
          height: 65,
          child: ElevatedButton(
            onPressed: _isLoading ? null : (_isDutyOn ? _markDutyOut : _markDutyIn),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isDutyOn ? Colors.red[600] : Colors.green[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 5,
              shadowColor: _isDutyOn ? Colors.red.withOpacity(0.4) : Colors.green.withOpacity(0.4),
            ),
            child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_isDutyOn ? Icons.logout : Icons.login, size: 28),
                  const SizedBox(width: 10),
                  Text(_isDutyOn ? 'DUTY OUT' : 'DUTY IN',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ]),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _buildTimeCard(String label, String time, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(time, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ]),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }
}

class FaceVerificationDialog extends StatefulWidget {
  final CameraDescription camera;
  final Function(bool) onVerified;
  const FaceVerificationDialog({super.key, required this.camera, required this.onVerified});
  @override
  State<FaceVerificationDialog> createState() => _FaceVerificationDialogState();
}

class _FaceVerificationDialogState extends State<FaceVerificationDialog> {
  CameraController? _controller;
  bool _isDetecting = false;
  String _status = 'Position your face in the frame';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _detectFace() async {
    if (_isDetecting || _controller == null) return;
    setState(() { _isDetecting = true; _status = 'Detecting face...'; });
    try {
      final image = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final detector = FaceDetector(options: FaceDetectorOptions(enableClassification: true));
      final faces = await detector.processImage(inputImage);
      await detector.close();
      if (faces.isNotEmpty) {
        setState(() => _status = 'Face verified! ✓');
        await Future.delayed(const Duration(milliseconds: 800));
        widget.onVerified(true);
      } else {
        setState(() { _status = 'No face detected. Try again.'; _isDetecting = false; });
      }
    } catch (e) {
      setState(() { _status = 'Error: Try again'; _isDetecting = false; });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Face Verification',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1D6FE8))),
          const SizedBox(height: 16),
          if (_controller != null && _controller!.value.isInitialized)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(height: 250, child: CameraPreview(_controller!)),
            )
          else
            const SizedBox(height: 250, child: Center(child: CircularProgressIndicator())),
          const SizedBox(height: 16),
          Text(_status, style: TextStyle(
            color: _status.contains('✓') ? Colors.green : 
                   _status.contains('No face') ? Colors.red : Colors.grey[700],
            fontWeight: FontWeight.w500,
          )),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => widget.onVerified(false),
              child: const Text('Cancel'),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: _isDetecting ? null : _detectFace,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D6FE8)),
              child: _isDetecting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Verify', style: TextStyle(color: Colors.white)),
            )),
          ]),
        ]),
      ),
    );
  }
}
