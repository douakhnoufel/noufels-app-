import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../services/classifier_service.dart';
import '../services/database_service.dart';
import 'result_screen.dart';
import 'live_camera_screen.dart';
import 'history_screen.dart';
import 'drone_stream_screen.dart';

class HomeScreen extends StatefulWidget {
  final ClassifierService classifier;
  const HomeScreen({super.key, required this.classifier});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final DatabaseService _db = DatabaseService();
  bool _isProcessing = false;

  void _openHistory() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HistoryScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _openLiveCamera() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => LiveCameraScreen(classifier: widget.classifier),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _openDroneStream() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => DroneStreamScreen(classifier: widget.classifier),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (file == null || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final full = await widget.classifier.classifyBytes(bytes);

      await _db.insertScan(ScanHistoryItem(
        label: full.result.label,
        confidence: full.result.confidence,
        timestamp: DateTime.now(),
        imageBytes: bytes,
      ));

      if (mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => ResultScreen(
              imageBytes: bytes,
              result: full.result,
              allProbabilities: full.probabilities,
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inference Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withValues(alpha: 0.08),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .scale(duration: 3.seconds, begin: const Offset(1, 1), end: const Offset(1.2, 1.2)),
          ),
          
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        colorScheme: colorScheme, 
                        textTheme: textTheme,
                        onHistoryTap: _openHistory,
                      ).animate().fadeIn(duration: 400.milliseconds).slideY(begin: -0.1),
                      
                      const SizedBox(height: 32),
                      
                      _HeroCard(colorScheme: colorScheme, textTheme: textTheme)
                          .animate().fadeIn(delay: 200.milliseconds).scale(begin: const Offset(0.95, 0.95)),
                      
                      const SizedBox(height: 40),
                      
                      Text(
                        'DIAGNOSIS METHODS',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ).animate().fadeIn(delay: 400.milliseconds),
                      
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: _ActionTile(
                              icon: Icons.add_a_photo_rounded,
                              label: 'Capture',
                              subtitle: 'Instant Photo',
                              onTap: () => _pickImage(ImageSource.camera),
                            ).animate().fadeIn(delay: 500.milliseconds).slideX(begin: -0.1),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ActionTile(
                              icon: Icons.collections_rounded,
                              label: 'Gallery',
                              subtitle: 'From Storage',
                              onTap: () => _pickImage(ImageSource.gallery),
                            ).animate().fadeIn(delay: 600.milliseconds).slideX(begin: 0.1),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),

                      _DiagnosisMethodRow(
                        onLiveTap: _openLiveCamera,
                        onDroneTap: _openDroneStream,
                      ).animate().fadeIn(delay: 700.milliseconds).slideY(begin: 0.1),
                      
                      const SizedBox(height: 40),
                      
                      _SupportedSection(colorScheme: colorScheme, textTheme: textTheme)
                          .animate().fadeIn(delay: 900.milliseconds),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_isProcessing) const _LoadingOverlay(),
        ],
      ),
    );
  }
}

class _DiagnosisMethodRow extends StatelessWidget {
  final VoidCallback onLiveTap;
  final VoidCallback onDroneTap;
  const _DiagnosisMethodRow({required this.onLiveTap, required this.onDroneTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _LiveActionButton(onTap: onLiveTap)),
        const SizedBox(width: 16),
        _DroneActionButton(onTap: onDroneTap),
      ],
    );
  }
}

class _DroneActionButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DroneActionButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: IconButton(
        onPressed: onTap,
        padding: const EdgeInsets.all(20),
        icon: Icon(Icons.airplanemode_active_rounded, color: colorScheme.primary),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onHistoryTap;
  const _Header({required this.colorScheme, required this.textTheme, required this.onHistoryTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.primaryContainer],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: const Icon(Icons.eco_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PlantGuard',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'SMART POTATO MONITOR',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const Spacer(),
        IconButton.filledTonal(
          onPressed: onHistoryTap,
          icon: const Icon(Icons.history_rounded, size: 22),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: () {},
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  const _HeroCard({required this.colorScheme, required this.textTheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(32),
        image: const DecorationImage(
          image: NetworkImage('https://images.unsplash.com/photo-1518977676601-b53f02bad67b?q=80&w=2070&auto=format&fit=crop'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black45,
            BlendMode.darken,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'YOLOv8 ENGINE',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Protect your\ncrops intelligently',
            style: textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scan potato leaves to detect diseases like Blight in milliseconds.',
            style: textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colorScheme.primary, size: 28),
              const SizedBox(height: 16),
              Text(label, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              Text(subtitle, style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveActionButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LiveActionButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20),
          backgroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        icon: const Icon(Icons.sensors_rounded),
        label: const Text(
          'LIVE SCAN',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
      ),
    );
  }
}

class _SupportedSection extends StatelessWidget {
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  const _SupportedSection({required this.colorScheme, required this.textTheme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SUPPORTED DIAGNOSIS',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.5),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        const _DiseaseItem(label: 'Early Blight', color: Color(0xFFFF8C42), icon: Icons.warning_amber_rounded),
        const SizedBox(height: 12),
        const _DiseaseItem(label: 'Late Blight', color: Color(0xFFE53935), icon: Icons.error_outline_rounded),
        const SizedBox(height: 12),
        const _DiseaseItem(label: 'Healthy Leaf', color: Color(0xFF43A047), icon: Icons.check_circle_outline_rounded),
      ],
    );
  }
}

class _DiseaseItem extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _DiseaseItem({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          const Icon(Icons.chevron_right, size: 16, color: Colors.white24),
        ],
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 24),
            const Text(
              'SYSTEM IS ANALYZING...',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2),
            ).animate(onPlay: (c) => c.repeat()).fadeIn(duration: 1.seconds).fadeOut(delay: 500.milliseconds),
          ],
        ),
      ),
    );
  }
}
