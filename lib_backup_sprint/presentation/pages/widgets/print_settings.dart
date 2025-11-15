import 'package:flutter/material.dart';

class PrintSettings extends StatefulWidget {
  final String designType;
  final int copies;
  final bool autoCut;
  final double density;
  final bool openDrawer;
  final bool gapDetection;
  final int darkness;
  final int speed;
  final Function(int, bool, double, bool, bool, int, int) onChanged;

  const PrintSettings({
    Key? key,
    required this.designType,
    required this.copies,
    required this.autoCut,
    required this.density,
    required this.openDrawer,
    this.gapDetection = false,
    this.darkness = 10,
    this.speed = 3,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<PrintSettings> createState() => _PrintSettingsState();
}

class _PrintSettingsState extends State<PrintSettings> {
  late int _copies;
  late bool _autoCut;
  late double _density;
  late bool _openDrawer;
  late bool _gapDetection;
  late int _darkness;
  late int _speed;
  
  @override
  void initState() {
    super.initState();
    _copies = widget.copies;
    _autoCut = widget.autoCut;
    _density = widget.density;
    _openDrawer = widget.openDrawer;
    _gapDetection = widget.gapDetection;
    _darkness = widget.darkness;
    _speed = widget.speed;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.print, size: 20),
            const SizedBox(width: 8),
            const Text('Yazdırma Ayarları', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 16),
        
        // Kopya sayısı
        Row(
          children: [
            const Text('Kopya Sayısı:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _copies.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: _copies.toString(),
                onChanged: (value) {
                  setState(() {
                    _copies = value.toInt();
                  });
                  _notifyChanges();
                },
              ),
            ),
            SizedBox(
              width: 30,
              child: Text('$_copies', textAlign: TextAlign.center),
            ),
          ],
        ),
        
        // Yazdırma yoğunluğu
        Row(
          children: [
            const Text('Yazdırma Yoğunluğu:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _density,
                min: 0.5,
                max: 1.5,
                divisions: 10,
                label: _density.toStringAsFixed(1),
                onChanged: (value) {
                  setState(() {
                    _density = value;
                  });
                  _notifyChanges();
                },
              ),
            ),
            SizedBox(
              width: 30,
              child: Text(_density.toStringAsFixed(1), textAlign: TextAlign.center),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Otomatik kesim
        SwitchListTile(
          title: const Text('Otomatik Kesim', style: TextStyle(fontWeight: FontWeight.w500)),
          subtitle: const Text('Yazdırma sonrası kağıdı otomatik kes'),
          value: _autoCut,
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            setState(() {
              _autoCut = value;
            });
            _notifyChanges();
          },
        ),
        
        // Çekmece açma (sadece fiş için)
        if (widget.designType == 'receipt')
          SwitchListTile(
            title: const Text('Para Çekmecesi', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Yazdırma sonrası para çekmecesini aç'),
            value: _openDrawer,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) {
              setState(() {
                _openDrawer = value;
              });
              _notifyChanges();
            },
          ),
        
        // Etiket ayarları (fiş dışındaki tüm türler için)
        if (widget.designType != 'receipt') ...[
          const SizedBox(height: 16),
          
          // Boşluk algılama
          SwitchListTile(
            title: const Text('Boşluk Algılama', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Etiketler arası boşluğu otomatik algıla'),
            value: _gapDetection,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) {
              setState(() {
                _gapDetection = value;
              });
              _notifyChanges();
            },
          ),
          
          // Koyuluk
          Row(
            children: [
              const Text('Koyuluk:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _darkness.toDouble(),
                  min: 0,
                  max: 15,
                  divisions: 15,
                  label: _darkness.toString(),
                  onChanged: (value) {
                    setState(() {
                      _darkness = value.toInt();
                    });
                    _notifyChanges();
                  },
                ),
              ),
              SizedBox(
                width: 30,
                child: Text('$_darkness', textAlign: TextAlign.center),
              ),
            ],
          ),
          
          // Hız
          Row(
            children: [
              const Text('Yazdırma Hızı:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _speed.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: _speed.toString(),
                  onChanged: (value) {
                    setState(() {
                      _speed = value.toInt();
                    });
                    _notifyChanges();
                  },
                ),
              ),
              SizedBox(
                width: 30,
                child: Text('$_speed', textAlign: TextAlign.center),
              ),
            ],
          ),
        ],
        
        const SizedBox(height: 16),
        
        // Test yazdırma butonu
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Test Yazdırma'),
            onPressed: () {
              _showPrintPreview(context);
            },
          ),
        ),
      ],
    );
  }

  void _notifyChanges() {
    widget.onChanged(_copies, _autoCut, _density, _openDrawer, _gapDetection, _darkness, _speed);
  }

  void _showPrintPreview(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yazdırma Önizleme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yazdırma ayarları:'),
            const SizedBox(height: 8),
            Text('• Kopya sayısı: $_copies'),
            Text('• Otomatik kesim: ${_autoCut ? "Açık" : "Kapalı"}'),
            Text('• Yazdırma yoğunluğu: ${_density.toStringAsFixed(1)}'),
            if (widget.designType == 'receipt')
              Text('• Para çekmecesi: ${_openDrawer ? "Açık" : "Kapalı"}'),
            if (widget.designType != 'receipt') ...[
              Text('• Boşluk algılama: ${_gapDetection ? "Açık" : "Kapalı"}'),
              Text('• Koyuluk: $_darkness'),
              Text('• Yazdırma hızı: $_speed'),
            ],
            const SizedBox(height: 16),
            const Text('Yazdırma işlemi başlatılsın mı?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Test yazdırma işlemi başlatıldı')),
              );
            },
            child: const Text('Yazdır'),
          ),
        ],
      ),
    );
  }
} 