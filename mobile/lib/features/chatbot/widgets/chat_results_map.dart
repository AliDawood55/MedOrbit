import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../discovery/models/location_models.dart';
import '../../discovery/widgets/discovery_map.dart';
import '../../discovery/widgets/place_marker.dart';
import '../models/chatbot_models.dart';
import 'chat_map_result_sheet.dart';

class ChatMapResult {
  const ChatMapResult({required this.id, required this.latitude, required this.longitude, required this.type, required this.label, this.subtitle, this.clinicId, this.doctorId});
  final String id; final double latitude; final double longitude; final DiscoveryPlaceType type; final String label; final String? subtitle; final String? clinicId; final String? doctorId;
  DiscoveryMapPlace get place => DiscoveryMapPlace(id: id, latitude: latitude, longitude: longitude, type: type, label: label);
}

class ChatResultsMap extends StatefulWidget {
  const ChatResultsMap({super.key, required this.places, required this.clinics, required this.doctors, this.userLocation, this.selectedId, this.onSelected});
  final List<ChatPlaceResult> places; final List<ChatPlaceResult> clinics; final List<ChatDoctorResult> doctors; final AppLocation? userLocation; final String? selectedId; final ValueChanged<String?>? onSelected;
  @override State<ChatResultsMap> createState() => _ChatResultsMapState();
}
class _ChatResultsMapState extends State<ChatResultsMap> {
  @override Widget build(BuildContext context) {
    final results = _results(context);
    final selected = results.where((item) => item.id == widget.selectedId).firstOrNull;
    if (results.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No mapped results are available.')));
    return Semantics(
      container: true,
      label: 'Map of chatbot care results',
      child: SizedBox(height: 360, child: Stack(children: [
        DiscoveryMap(places: results.map((item) => item.place).toList(), userLocation: widget.userLocation, initialCenter: LatLng(results.first.latitude, results.first.longitude), onPlaceTap: (place) => widget.onSelected?.call(place.id)),
        if (selected != null) PositionedDirectional(start: 12, end: 12, bottom: 12, child: ChatMapResultSheet(result: selected, onClose: () => widget.onSelected?.call(null))),
      ])),
    );
  }
  List<ChatMapResult> _results(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final values = <ChatMapResult>[];
    void addPlace(ChatPlaceResult item, {bool clinic = false}) { final lat = item.latitude; final lng = item.longitude; if (lat == null || lng == null) return; final name = (rtl ? item.nameAr ?? item.nameEn : item.nameEn ?? item.nameAr)?.trim(); values.add(ChatMapResult(id: '${clinic ? 'clinic' : 'place'}-${item.id}', latitude: lat, longitude: lng, type: DiscoveryPlaceType.fromString(item.type), label: name?.isNotEmpty == true ? name! : 'Place', subtitle: [item.type, item.city ?? item.region].whereType<String>().join(' · '), clinicId: clinic && item.id.isNotEmpty ? item.id : null)); }
    for (final item in widget.places) {
      addPlace(item);
    }
    for (final item in widget.clinics) {
      addPlace(item, clinic: true);
    }
    for (final item in widget.doctors) { final lat = item.metadata.latitude; final lng = item.metadata.longitude; if (item.clinicId?.isEmpty != false || lat == null || lng == null) continue; final name = [(rtl ? item.firstNameAr ?? item.firstNameEn : item.firstNameEn ?? item.firstNameAr), (rtl ? item.lastNameAr ?? item.lastNameEn : item.lastNameEn ?? item.lastNameAr)].whereType<String>().join(' ').trim(); values.add(ChatMapResult(id: 'doctor-${item.id}', latitude: lat, longitude: lng, type: DiscoveryPlaceType.doctor, label: name.isEmpty ? 'Doctor' : name, subtitle: rtl ? item.specialtyAr ?? item.specialtyEn : item.specialtyEn ?? item.specialtyAr, doctorId: item.id.isNotEmpty ? item.id : null, clinicId: item.clinicId)); }
    return values;
  }
}

extension _FirstOrNull<T> on Iterable<T> { T? get firstOrNull => isEmpty ? null : first; }
