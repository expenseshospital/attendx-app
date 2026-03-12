import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> employeeData;
  const ProfileScreen({super.key, required this.employeeData});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _faceRegistered = false;
  bool _isRegistering = false;

  @override
  void initState() {
    super.initState();
    _faceRegistered = widget.employeeData['face_registered'] == true;
  }

  Future<void> _registerFace() async {
    setState(() => _isRegistering = true);
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      bool success = false;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _FaceRegisterDialog(
          camera: frontCamera,
          onComplete: (result) {
            success = result;
            Navigator.pop(context);
          },
        ),
      );
      if (success) {
        await Supabase.instance.client
            .from('employees')
            .update({'face_registered': true})
            .eq('id', widget.employeeData['id']);
        setState(() => _faceRegistered = true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Face registered successfully!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: \$e'),
        backgroundColor: Colors.red,
      ));
    }
    setState(() => _isRegistering = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 50,
            backgroundColor: const Color(0xFF1D6FE8),
            child: Text(
              (widget.employeeData['name'] ?? 'E')[0].toUpperCase(),
              style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.employeeData['name'] ?? 'Employee',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(widget.employeeData['job_role'] ?? '',
            style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 24),

          _infoCard('Employee ID', widget.employeeData['employee_code'] ?? 'N/A', Icons.badge),
          _infoCard('Mobile', widget.employeeData['mobile'] ?? 'N/A', Icons.phone),
          _infoCard('Employee Type', widget.employeeData['employee_type'] ?? 'N/A', Icons.work),
          _infoCard('Face Registered', _faceRegistered ? 'Yes ✅' : 'No ❌', Icons.face),
          const SizedBox(height: 16),

          // Face Registration Button
          if (!_faceRegistered)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                onPressed: _isRegistering ? null : _registerFace,
                icon: _isRegistering
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.face_retouching_natural),
                label: Text(_isRegistering ? 'Registering...' : 'Register Face',
                  style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D6FE8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Face Registered Successfully', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ]),
            ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false);
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF1D6FE8)),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
      ]),
    );
  }
}

class _FaceRegisterDialog extends StatefulWidget {
  final CameraDescription camera;
  final Function(bool) onComplete;
  const _FaceRegisterDialog({required this.camera, required this.onComplete});
  @override
  State<_FaceRegisterDialog> createState() => _FaceRegisterDialogState();
}

class _FaceRegisterDialogState extends State<_FaceRegisterDialog> {
  CameraController? _controller;
  bool _isProcessing = false;
  String _status = 'Look straight at the camera and click Capture';

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

  Future<void> _captureFace() async {
    if (_isProcessing || _controller == null) return;
    setState(() { _isProcessing = true; _status = 'Detecting face...'; });
    try {
      final image = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final detector = FaceDetector(options: FaceDetectorOptions());
      final faces = await detector.processImage(inputImage);
      await detector.close();
      if (faces.isNotEmpty) {
        setState(() => _status = 'Face captured successfully! ✓');
        await Future.delayed(const Duration(milliseconds: 800));
        widget.onComplete(true);
      } else {
        setState(() { _status = 'No face detected. Please try again.'; _isProcessing = false; });
      }
    } catch (e) {
      setState(() { _status = 'Error. Please try again.'; _isProcessing = false; });
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
          const Text('Register Face', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1D6FE8))),
          const SizedBox(height: 8),
          const Text('This will be used to verify your identity', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),
          if (_controller != null && _controller!.value.isInitialized)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(height: 260, child: CameraPreview(_controller!)),
            )
          else
            const SizedBox(height: 260, child: Center(child: CircularProgressIndicator())),
          const SizedBox(height: 16),
          Text(_status, textAlign: TextAlign.center, style: TextStyle(
            color: _status.contains('✓') ? Colors.green :
                   _status.contains('No face') ? Colors.red : Colors.grey[700],
            fontWeight: FontWeight.w500,
          )),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => widget.onComplete(false),
              child: const Text('Cancel'),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _captureFace,
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: Text(_isProcessing ? 'Processing...' : 'Capture',
                style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D6FE8)),
            )),
          ]),
        ]),
      ),
    );
  }
}
