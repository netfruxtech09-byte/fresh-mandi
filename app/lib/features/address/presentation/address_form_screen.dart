import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/fresh_app_bar.dart';
import '../data/address_repository.dart';

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key, this.addressId});
  final int? addressId;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'Home');
  final _line1 = TextEditingController();
  final _pincode = TextEditingController();

  bool _isDefault = false;
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _sectors = const [];
  List<Map<String, dynamic>> _buildings = const [];
  List<String> _cities = const ['Mohali'];
  String _selectedCity = 'Mohali';
  String _selectedState = 'Punjab';
  Set<String> _allowedPincodes = const {};
  int? _selectedSectorId;
  int? _selectedBuildingId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _label.dispose();
    _line1.dispose();
    _pincode.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final repo = ref.read(addressRepositoryProvider);
      final serviceability = await repo.fetchServiceability();
      final cities = ((serviceability['cities'] as List?) ?? const [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      _cities = cities.isEmpty ? const ['Mohali'] : cities;
      _selectedCity = '${serviceability['city'] ?? _cities.first}'.trim();
      if (_selectedCity.isEmpty || !_cities.contains(_selectedCity)) {
        _selectedCity = _cities.first;
      }
      _selectedState = '${serviceability['state'] ?? 'Punjab'}'.trim();
      _allowedPincodes = (((serviceability['pincodes'] as List?) ?? const [])
          .map((e) => '$e'.trim())
          .where((e) => RegExp(r'^\d{6}$').hasMatch(e))).toSet();

      _sectors = await repo.fetchSectors();
      final all = await ref.read(addressRepositoryProvider).fetchAddresses();
      if (widget.addressId == null) {
        _isDefault = all.isEmpty;
      } else {
        final current = all.firstWhere(
          (a) =>
              ((a['id'] as num?)?.toInt() ?? int.tryParse('${a['id']}')) ==
              widget.addressId,
          orElse: () => <String, dynamic>{},
        );
        if (current.isNotEmpty) {
          _label.text = '${current['label'] ?? 'Home'}';
          _line1.text = '${current['line1'] ?? ''}';
          final currentCity = '${current['city'] ?? ''}'.trim();
          if (currentCity.isNotEmpty && _cities.contains(currentCity)) {
            _selectedCity = currentCity;
          }
          final currentState = '${current['state'] ?? ''}'.trim();
          if (currentState.isNotEmpty) _selectedState = currentState;
          _pincode.text = '${current['pincode'] ?? ''}';
          _selectedSectorId = (current['sector_id'] as num?)?.toInt() ??
              int.tryParse('${current['sector_id']}');
          _selectedBuildingId = (current['building_id'] as num?)?.toInt() ??
              int.tryParse('${current['building_id']}');
          _isDefault = current['is_default'] == true;
        }
      }

      if (_selectedSectorId == null && _sectors.isNotEmpty) {
        _selectedSectorId = (_sectors.first['id'] as num?)?.toInt();
      }
      if (_selectedSectorId != null) {
        _buildings = await repo.fetchBuildings(sectorId: _selectedSectorId!);
        final buildingExists = _buildings.any(
          (b) =>
              ((b['id'] as num?)?.toInt() ?? int.tryParse('${b['id']}')) ==
              _selectedBuildingId,
        );
        if (!buildingExists) _selectedBuildingId = null;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onSectorChanged(int? sectorId) async {
    if (sectorId == null) return;
    setState(() {
      _selectedSectorId = sectorId;
      _selectedBuildingId = null;
      _buildings = const [];
      _loading = true;
    });
    try {
      _buildings = await ref
          .read(addressRepositoryProvider)
          .fetchBuildings(sectorId: sectorId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      AppFeedback.error(context, 'Please fill all fields correctly.');
      return;
    }
    if (_selectedSectorId == null || _selectedSectorId! <= 0) {
      AppFeedback.error(context, 'Please select sector.');
      return;
    }
    final normalizedPincode = _pincode.text.trim();
    if (_allowedPincodes.isNotEmpty &&
        !_allowedPincodes.contains(normalizedPincode)) {
      AppFeedback.error(
          context, 'Currently we are not delivering at this pincode.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(addressRepositoryProvider);
      if (widget.addressId == null) {
        await repo.createAddress(
          label: _label.text.trim(),
          line1: _line1.text.trim(),
          city: _selectedCity,
          state: _selectedState,
          pincode: normalizedPincode,
          sectorId: _selectedSectorId!,
          buildingId: _selectedBuildingId,
          isDefault: _isDefault,
        );
      } else {
        await repo.updateAddress(
          id: widget.addressId!,
          label: _label.text.trim(),
          line1: _line1.text.trim(),
          city: _selectedCity,
          state: _selectedState,
          pincode: normalizedPincode,
          sectorId: _selectedSectorId!,
          buildingId: _selectedBuildingId,
          isDefault: _isDefault,
        );
      }

      if (!mounted) return;
      context.pop(true);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.error(context, 'Unable to save address. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: DT.bg,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return Scaffold(
      backgroundColor: DT.bg,
      appBar: FreshAppBar(
          title: widget.addressId == null ? 'Add Address' : 'Edit Address'),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: DT.softShadow),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labelText('Address Label'),
                    const SizedBox(height: 6),
                    _input(_label,
                        hint: 'Home, Office',
                        validator: Validators.addressLabel),
                    const SizedBox(height: 10),
                    _labelText('Address Line'),
                    const SizedBox(height: 6),
                    _input(_line1,
                        hint: 'House no., Street, Landmark',
                        validator: (v) => Validators.minLength(v,
                            min: 2, label: 'Address line')),
                    const SizedBox(height: 10),
                    _labelText('City'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCity,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF2F4F7),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: Color(0xFF86EFAC), width: 1),
                        ),
                      ),
                      items: _cities
                          .map((city) =>
                              DropdownMenuItem(value: city, child: Text(city)))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedCity = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    _labelText('Sector'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedSectorId,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF2F4F7),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: Color(0xFF86EFAC), width: 1),
                        ),
                      ),
                      items: _sectors
                          .map((s) {
                            final id = (s['id'] as num?)?.toInt() ??
                                int.tryParse('${s['id']}');
                            if (id == null) return null;
                            return DropdownMenuItem<int>(
                              value: id,
                              child: Text(
                                  '${s['name'] ?? 'Sector'} (${s['code'] ?? '-'})'),
                            );
                          })
                          .whereType<DropdownMenuItem<int>>()
                          .toList(),
                      onChanged: (v) => _onSectorChanged(v),
                      validator: (v) =>
                          (v == null || v <= 0) ? 'Sector is required' : null,
                    ),
                    const SizedBox(height: 10),
                    _labelText('Building (Optional)'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedBuildingId,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF2F4F7),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: Color(0xFF86EFAC), width: 1),
                        ),
                      ),
                      items: [
                        ..._buildings.map((b) {
                          final id = (b['id'] as num?)?.toInt() ??
                              int.tryParse('${b['id']}');
                          if (id == null) return null;
                          return DropdownMenuItem<int>(
                            value: id,
                            child: Text(
                                '${b['name'] ?? 'Building'} (${b['code'] ?? '-'})'),
                          );
                        }).whereType<DropdownMenuItem<int>>(),
                      ],
                      onChanged: (v) => setState(() => _selectedBuildingId = v),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelText('State'),
                              const SizedBox(height: 6),
                              TextFormField(
                                initialValue: _selectedState,
                                readOnly: true,
                                decoration: InputDecoration(
                                  hintText: 'State',
                                  counterText: '',
                                  hintStyle: const TextStyle(
                                      color: Color(0xFF6B7280), fontSize: 14.5),
                                  filled: true,
                                  fillColor: const Color(0xFFF2F4F7),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: Color(0xFF86EFAC), width: 1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelText('Pincode'),
                              const SizedBox(height: 6),
                              _input(
                                _pincode,
                                hint: '160055',
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                validator: Validators.indianPincode,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_allowedPincodes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Serviceable pincodes: ${_allowedPincodes.take(8).join(', ')}${_allowedPincodes.length > 8 ? ' ...' : ''}',
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xFF475467)),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      value: _isDefault,
                      onChanged: (v) => setState(() => _isDefault = v),
                      activeThumbColor: Colors.white,
                      activeTrackColor: DT.primaryDark,
                      title: const Text('Set as default address',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14.5)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.pop(),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Cancel',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: DT.primaryDark,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Save Address',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelText(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 14.5, fontWeight: FontWeight.w600, color: DT.text));
  }

  Widget _input(
    TextEditingController controller, {
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 14.5),
        filled: true,
        fillColor: const Color(0xFFF2F4F7),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF86EFAC), width: 1),
        ),
      ),
    );
  }
}
