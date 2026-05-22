import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

part 'listing_model.g.dart';

@HiveType(typeId: 0)
class ListingModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final String type; // 'lost' | 'found'

  @HiveField(4)
  final String location;

  @HiveField(5)
  final String? photoUrl;

  @HiveField(6)
  final String ownerId;

  @HiveField(7)
  final String ownerEmail;

  @HiveField(8)
  final String ownerName;

  @HiveField(9)
  final bool isResolved;

  @HiveField(10)
  final DateTime createdAt;

  @HiveField(11)
  final DateTime? updatedAt;

  @HiveField(12)
  final String? category;

  @HiveField(13)
  final bool chatEnabled;

  @HiveField(14)
  final String? pickupNote;

  @HiveField(15)
  final int commentCount;

  ListingModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.location,
    this.photoUrl,
    required this.ownerId,
    required this.ownerEmail,
    required this.ownerName,
    required this.isResolved,
    required this.createdAt,
    this.updatedAt,
    this.category,
    this.chatEnabled = true,
    this.pickupNote,
    this.commentCount = 0,
  });

  factory ListingModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ListingModel(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      type: data['type'] ?? 'lost',
      location: data['location'] ?? '',
      photoUrl: data['photoUrl'],
      ownerId: data['ownerId'] ?? '',
      ownerEmail: data['ownerEmail'] ?? '',
      ownerName: data['ownerName'] ?? 'Anonymous',
      isResolved: data['isResolved'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      category: data['category'],
      // Default to chat enabled for legacy listings without the field.
      chatEnabled: data['chatEnabled'] ?? true,
      pickupNote: data['pickupNote'],
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'type': type,
      'location': location,
      'photoUrl': photoUrl,
      'ownerId': ownerId,
      'ownerEmail': ownerEmail,
      'ownerName': ownerName,
      'isResolved': isResolved,
      'category': category,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? FieldValue.serverTimestamp() : null,
    };
  }

  ListingModel copyWith({
    String? title,
    String? description,
    String? type,
    String? location,
    String? photoUrl,
    bool? isResolved,
    String? category,
    bool? chatEnabled,
    String? pickupNote,
  }) {
    return ListingModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      location: location ?? this.location,
      photoUrl: photoUrl ?? this.photoUrl,
      ownerId: ownerId,
      ownerEmail: ownerEmail,
      ownerName: ownerName,
      isResolved: isResolved ?? this.isResolved,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      category: category ?? this.category,
      chatEnabled: chatEnabled ?? this.chatEnabled,
      pickupNote: pickupNote ?? this.pickupNote,
    );
  }
}

// Campus location options
const List<String> campusLocations = [
  'Main Library',
  'Student Union',
  'Engineering Building',
  'Science Hall',
  'Arts Center',
  'Dining Hall',
  'Gym & Recreation',
  'Residence Halls',
  'Parking Lots',
  'Campus Grounds',
  'Other',
];

// Item category options
const List<String> itemCategories = [
  'Electronics',
  'Books & Notebooks',
  'Clothing & Accessories',
  'Keys & Cards',
  'Sports Equipment',
  'Personal Items',
  'Other',
];