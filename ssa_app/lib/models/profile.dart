class Profile {
  final String name;

  Profile(this.name) {
    if (name.trim().isEmpty) {
      throw ArgumentError('Profile name must not be empty.');
    }
  }

  String get trimmedName => name.trim();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile &&
          runtimeType == other.runtimeType &&
          trimmedName == other.trimmedName;

  @override
  int get hashCode => trimmedName.hashCode;

  @override
  String toString() => 'Profile($trimmedName)';
}
