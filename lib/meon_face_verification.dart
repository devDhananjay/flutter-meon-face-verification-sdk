import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef MeonVerificationSuccessCallback = void Function(
    Map<String, dynamic> data);
typedef MeonVerificationErrorCallback = void Function(String message);
typedef MeonVerificationCloseCallback = void Function();

/// Flutter mirror of the React Native MeonFaceVerification component.
class VerificationConfig {
  final bool checkLocation;
  final bool captureVideo;
  final bool matchFace;
  final bool readScript;
  final String textScript;
  final int videoTime;
  final String imageToBeMatch;

  const VerificationConfig({
    this.checkLocation = false,
    this.captureVideo = false,
    this.matchFace = false,
    this.readScript = false,
    this.textScript = "Please complete the verification process",
    this.videoTime = 10,
    this.imageToBeMatch = "",
  });

  Map<String, dynamic> toJson() => {
        'check_location': checkLocation,
        'capture_video': captureVideo,
        'match_face': matchFace,
        'read_script': readScript,
        'text_script': textScript,
        'video_time': videoTime,
        'image_to_be_match': imageToBeMatch,
      };
}

class MeonFaceVerification extends StatefulWidget {
  final String clientId;
  final String clientSecret;
  final MeonVerificationSuccessCallback? onSuccess;
  final MeonVerificationErrorCallback? onError;
  final MeonVerificationCloseCallback? onClose;

  final bool showHeader;
  final String headerTitle;
  final String baseUrl;
  final bool autoRequestPermissions;
  final VerificationConfig verificationConfig;

  const MeonFaceVerification({
    Key? key,
    required this.clientId,
    required this.clientSecret,
    this.onSuccess,
    this.onError,
    this.onClose,
    this.showHeader = true,
    this.headerTitle = 'Face Verification',
    this.baseUrl = 'https://face-finder.meon.co.in',
    this.autoRequestPermissions = true,
    this.verificationConfig = const VerificationConfig(),
  }) : super(key: key);

  @override
  State<MeonFaceVerification> createState() => _MeonFaceVerificationState();
}

class _MeonFaceVerificationState extends State<MeonFaceVerification> {
  late final WebViewController _webViewController;

  bool _isLoading = true;
  bool _webViewLoading = false;
  bool _isProcessingComplete = false;
  bool _permissionsGranted = false;

  String? _error;
  String? _verificationUrl;
  String? _transactionId;
  Map<String, dynamic>? _resultData;
  bool _showResultModal = false;

  bool get _isNormalVerification => widget.verificationConfig.matchFace == false;

  @override
  void initState() {
    super.initState();
    _initWebViewController();
    _initializeFaceVerification();
  }

  void _initWebViewController() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/91.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _webViewLoading = true;
            });
          },
          onPageFinished: (url) async {
            setState(() {
              _webViewLoading = false;
            });
            await _injectPermissionScript();
          },
          onWebResourceError: (error) {
            debugPrint('[FaceVerification] WebView error: $error');
            setState(() {
              _webViewLoading = false;
            });
          },
          onNavigationRequest: (request) {
            debugPrint('[FaceVerification] URL loading: ${request.url}');
            if (_shouldInterceptUrl(request.url) && !_isProcessingComplete) {
              _handleVerificationCompletion();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
  }

  bool _shouldInterceptUrl(String url) {
    final lower = url.toLowerCase();
    return (lower.contains('success') ||
            lower.contains('complete') ||
            lower.contains('finished')) &&
        !_isProcessingComplete;
  }

  Future<bool> _requestPermissions() async {
    try {
      debugPrint('[FaceVerification] Requesting permissions...');

      final statuses = await [
        Permission.camera,
        Permission.microphone,
        Permission.locationWhenInUse,
      ].request();

      final allGranted =
          statuses.values.every((status) => status.isGranted == true);

      if (allGranted) {
        debugPrint('[FaceVerification] All permissions granted');
        setState(() {
          _permissionsGranted = true;
        });
        return true;
      } else {
        _handlePermissionDenied(statuses);
        return false;
      }
    } catch (e) {
      debugPrint('[FaceVerification] Error requesting permissions: $e');
      _showAlert(
        title: 'Permission Error',
        message: 'Failed to request permissions. Please try again.',
      );
      return false;
    }
  }

  void _handlePermissionDenied(
      Map<Permission, PermissionStatus> statuses) async {
    final deniedPermissions = <String>[];

    if (!statuses[Permission.camera]!.isGranted) {
      deniedPermissions.add('Camera');
    }
    if (!statuses[Permission.microphone]!.isGranted) {
      deniedPermissions.add('Microphone');
    }
    if (!statuses[Permission.locationWhenInUse]!.isGranted) {
      deniedPermissions.add('Location');
    }

    if (deniedPermissions.isNotEmpty && mounted) {
      final context = this.context;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permissions Required'),
          content: Text(
            'Face verification requires ${deniedPermissions.join(', ')} permission(s) to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.onClose?.call();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _requestPermissions();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _generateToken({String? transactionId}) async {
    final uri = Uri.parse(
        '${widget.baseUrl}/backend/generate_token_for_ipv_credentials');
    final body = <String, dynamic>{
      'client_id': widget.clientId,
      'client_secret': widget.clientSecret,
      if (transactionId != null) 'transaction_id': transactionId,
    };

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint('[FaceVerification] Token generated: $data');

    if (data['code'] == 200 &&
        data['success'] == true &&
        data['data'] != null &&
        (data['data'] as Map)['token'] != null) {
      return data;
    }

    throw Exception(data['msg'] ?? 'Failed to generate token');
  }

  Future<Map<String, dynamic>> _initiateRequest(String token) async {
    final uri = Uri.parse('${widget.baseUrl}/backend/initiate_request');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'token': token,
      },
      body: jsonEncode(widget.verificationConfig.toJson()),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint('[FaceVerification] Request initiated: $data');

    if (data['code'] == 200 &&
        data['success'] == true &&
        data['data'] != null &&
        (data['data'] as Map)['url'] != null &&
        (data['data'] as Map)['transaction_id'] != null) {
      return data;
    }

    throw Exception(data['msg'] ?? 'Failed to initiate request');
  }

  Future<Map<String, dynamic>> _exportData(String token) async {
    final uri = Uri.parse('${widget.baseUrl}/backend/export_data');

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'token': token,
      },
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint('[FaceVerification] Data exported: $data');

    if (data['code'] == 200 &&
        data['success'] == true &&
        data['data'] != null) {
      return data;
    }

    throw Exception(data['msg'] ?? 'Failed to export data');
  }

  Future<void> _initializeFaceVerification() async {
    if (widget.clientId.isEmpty || widget.clientSecret.isEmpty) {
      const msg = 'clientId and clientSecret are required';
      setState(() {
        _error = msg;
        _isLoading = false;
      });
      widget.onError?.call(msg);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.autoRequestPermissions) {
        final ok = await _requestPermissions();
        if (!ok) {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      final tokenData = await _generateToken();
      final token = (tokenData['data'] as Map)['token'] as String;

      final initiateData = await _initiateRequest(token);
      final data = initiateData['data'] as Map;

      final url = data['url'] as String;
      final transactionId = data['transaction_id'] as String;

      setState(() {
        _verificationUrl = url;
        _transactionId = transactionId;
        _isLoading = false;
      });

      await _webViewController.loadRequest(Uri.parse(url));
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _error = msg;
        _isLoading = false;
      });
      widget.onError?.call(msg);
    }
  }

  Future<void> _handleVerificationCompletion() async {
    if (_isProcessingComplete || _transactionId == null) return;

    setState(() {
      _isProcessingComplete = true;
      _webViewLoading = true;
    });

    try {
      debugPrint('[FaceVerification] Processing completion...');

      final tokenData =
          await _generateToken(transactionId: _transactionId ?? '');
      final token = (tokenData['data'] as Map)['token'] as String;

      final exportResult = await _exportData(token);

      if (exportResult['code'] == 200 && exportResult['success'] == true) {
        final data = exportResult['data'] as Map<String, dynamic>;
        setState(() {
          _resultData = data;
          _showResultModal = true;
        });
        widget.onSuccess?.call(data);
      } else {
        _showAlert(
          title: 'Error',
          message: 'Verification completed but failed to export data.',
          onOk: () => widget.onClose?.call(),
        );
      }
    } catch (e) {
      debugPrint('[FaceVerification] Completion error: $e');
      _showAlert(
        title: 'Error',
        message: 'An error occurred while processing verification data.',
        onOk: () => widget.onClose?.call(),
      );
    } finally {
      if (mounted) {
        setState(() {
          _webViewLoading = false;
        });
      }
    }
  }

  Future<void> _injectPermissionScript() async {
    final script = '''
      (function() {
        const storePermission = (name, state) => { 
          try { 
            sessionStorage.setItem('permission_' + name, state); 
            localStorage.setItem('permission_' + name, state); 
            console.log('[FaceVerification] Permission stored:', name, state);
          } catch(e) { 
            console.error('[FaceVerification] Storage error:', e);
          } 
        };
        
        const permissions = ['camera', 'microphone', 'geolocation'];
        const permissionsGranted = ${_permissionsGranted ? 'true' : 'false'};
        
        permissions.forEach(p => storePermission(p, permissionsGranted ? 'granted' : 'denied'));
        
        if (navigator.permissions?.query) {
          const originalQuery = navigator.permissions.query;
          navigator.permissions.query = function(desc) {
            console.log('[FaceVerification] Permission query:', desc.name);
            if (permissions.includes(desc.name)) {
              return Promise.resolve({ 
                state: permissionsGranted ? 'granted' : 'denied', 
                onchange: null 
              });
            }
            return originalQuery.call(this, desc);
          };
        }
        
        if (navigator.mediaDevices?.getUserMedia) {
          const originalGetUserMedia = navigator.mediaDevices.getUserMedia;
          navigator.mediaDevices.getUserMedia = function(constraints) {
            console.log('[FaceVerification] getUserMedia called:', constraints);
            if (!permissionsGranted) {
              return Promise.reject(new Error('Permissions not granted'));
            }
            if (constraints.video) storePermission('camera', 'granted');
            if (constraints.audio) storePermission('microphone', 'granted');
            return originalGetUserMedia.call(this, constraints);
          };
        }
        
        if (navigator.geolocation?.getCurrentPosition) {
          const originalGetPosition = navigator.geolocation.getCurrentPosition;
          navigator.geolocation.getCurrentPosition = function(success, error, options) {
            console.log('[FaceVerification] Geolocation requested');
            if (!permissionsGranted) {
              if (error) error({ code: 1, message: 'Permission denied' });
              return;
            }
            storePermission('geolocation', 'granted');
            return originalGetPosition.call(this, success, error, options);
          };
        }
        
        window.addEventListener('load', function() {
          console.log('[FaceVerification] Page loaded, permissions:', permissionsGranted);
          if (permissionsGranted) {
            permissions.forEach(p => storePermission(p, 'granted'));
          }
        });
        
        console.log('[FaceVerification] Permission script initialized');
      })();
      true;
    ''';

    try {
      await _webViewController.runJavaScript(script);
    } catch (e) {
      debugPrint('[FaceVerification] Error injecting JS: $e');
    }
  }

  bool _isVerificationSuccessful() {
    if (_isNormalVerification) {
      return true;
    }
    final facesMatched = _resultData?['faces_matched'];
    return facesMatched == true || facesMatched == "";
  }

  void _handleClose() {
    if (!mounted) return;
    final context = this.context;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Verification'),
        content: const Text('Are you sure you want to close?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onClose?.call();
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (await _webViewController.canGoBack()) {
      _webViewController.goBack();
      return false;
    }

    if (!mounted) return true;
    final context = this.context;
    final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit Verification'),
            content: const Text('Are you sure you want to exit?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Exit'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldExit) {
      widget.onClose?.call();
    }
    return shouldExit;
  }

  void _handleCompletePress() {
    setState(() {
      _showResultModal = false;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      widget.onClose?.call();
    });
  }

  void _showAlert({
    required String title,
    required String message,
    VoidCallback? onOk,
  }) {
    if (!mounted) return;
    final context = this.context;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onOk?.call();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: Color(0xFF0047AB)),
            SizedBox(height: 16),
            Text(
              'Initializing Face Verification...',
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B6B),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _error = null;
                  });
                  _initializeFaceVerification();
                },
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_verificationUrl == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Failed to load verification URL',
              style: TextStyle(
                fontSize: 16,
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B6B),
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _initializeFaceVerification,
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _onWillPop().then((shouldPop) {
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop(result);
          }
        });
      },
      child: Column(
        children: [
          if (widget.showHeader) _buildHeader(context),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _webViewController),
                if (_webViewLoading)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0047AB),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Processing...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_showResultModal && _resultData != null)
                  _buildResultModal(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE0E0E0)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            InkWell(
              onTap: () async {
                if (await _webViewController.canGoBack()) {
                  _webViewController.goBack();
                } else {
                  _onWillPop();
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.headerTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Meon SDK',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF0047AB),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: _handleClose,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0x1AD32F2F),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.close,
                  color: Color(0xFFD32F2F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultModal(BuildContext context) {
    final isSuccess = _isVerificationSuccessful();
    final data = _resultData!;

    return Material(
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                Text(
                  'Verification Complete',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Your face verification has been successfully completed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildImageColumn(
                        label: 'Captured Image',
                        url: data['image'] as String?,
                      ),
                      if (!_isNormalVerification &&
                          (data['image_to_be_matched'] as String?) != null &&
                          (data['image_to_be_matched'] as String).isNotEmpty)
                        _buildImageColumn(
                          label: 'Reference Image',
                          url: data['image_to_be_matched'] as String?,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (!_isNormalVerification) ...[
                    const Text(
                      'Verification Status',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSuccess
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSuccess
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFF44336),
                        ),
                      ),
                      child: Text(
                        isSuccess
                            ? '✓ Verified Successfully'
                            : '✗ Face Mismatch',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSuccess
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (data['location'] != null) ...[
                    const Text(
                      'Location',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoBox(
                      data['location']?.toString() ?? 'N/A',
                      minHeight: 50,
                    ),
                    const SizedBox(height: 20),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Latitude',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildInfoBox(
                              data['latitude']?.toString() ?? 'N/A',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Longitude',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildInfoBox(
                              data['longitude']?.toString() ?? 'N/A',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (data['timestamp'] != null) ...[
                    const Text(
                      'Timestamp',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoBox(
                      _formatTimestamp(data['timestamp']),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 40),
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.7,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isSuccess ? const Color(0xFF4CAF50) : Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: _handleCompletePress,
                child: Text(
                  isSuccess ? 'Continue' : 'Retry Verification',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageColumn({required String label, String? url}) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFF5F5F5),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            clipBehavior: Clip.antiAlias,
            child: url != null && url.isNotEmpty
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text(
                        'No Image',
                        style:
                            TextStyle(fontSize: 14, color: Colors.black45),
                      ),
                    ),
                  )
                : const Center(
                    child: Text(
                      'No Image',
                      style: TextStyle(fontSize: 14, color: Colors.black45),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(String text, {double minHeight = 0}) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic value) {
    try {
      if (value is String) {
        return DateTime.parse(value).toLocal().toString();
      }
      return value.toString();
    } catch (_) {
      return value.toString();
    }
  }
}

