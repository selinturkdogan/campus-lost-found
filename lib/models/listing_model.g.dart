// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listing_model.dart';

class ListingModelAdapter extends TypeAdapter<ListingModel> {
  @override
  final int typeId = 0;

  @override
  ListingModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ListingModel(
      id: fields[0] as String,
      title: fields[1] as String,
      description: fields[2] as String,
      type: fields[3] as String,
      location: fields[4] as String,
      photoUrl: fields[5] as String?,
      ownerId: fields[6] as String,
      ownerEmail: fields[7] as String,
      ownerName: fields[8] as String,
      isResolved: fields[9] as bool,
      createdAt: fields[10] as DateTime,
      updatedAt: fields[11] as DateTime?,
      category: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ListingModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.location)
      ..writeByte(5)
      ..write(obj.photoUrl)
      ..writeByte(6)
      ..write(obj.ownerId)
      ..writeByte(7)
      ..write(obj.ownerEmail)
      ..writeByte(8)
      ..write(obj.ownerName)
      ..writeByte(9)
      ..write(obj.isResolved)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.updatedAt)
      ..writeByte(12)
      ..write(obj.category);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListingModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}