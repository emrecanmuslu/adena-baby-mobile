// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $RecordsTable extends Records with TableInfo<$RecordsTable, RecordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _babyMeta = const VerificationMeta('baby');
  @override
  late final GeneratedColumn<String> baby = GeneratedColumn<String>(
    'baby',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<DateTime> ts = GeneratedColumn<DateTime>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    baby,
    type,
    ts,
    data,
    createdBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'records';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('baby')) {
      context.handle(
        _babyMeta,
        baby.isAcceptableOrUnknown(data['baby']!, _babyMeta),
      );
    } else if (isInserting) {
      context.missing(_babyMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    } else if (isInserting) {
      context.missing(_tsMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecordRow(
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      baby: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baby'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ts'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
    );
  }

  @override
  $RecordsTable createAlias(String alias) {
    return $RecordsTable(attachedDatabase, alias);
  }
}

class RecordRow extends DataClass implements Insertable<RecordRow> {
  final bool isDeleted;
  final DateTime? clientUpdatedAt;
  final DateTime? serverUpdatedAt;
  final bool dirty;
  final String id;
  final String baby;
  final String type;
  final DateTime ts;
  final String data;
  final String? createdBy;
  const RecordRow({
    required this.isDeleted,
    this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.dirty,
    required this.id,
    required this.baby,
    required this.type,
    required this.ts,
    required this.data,
    this.createdBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || clientUpdatedAt != null) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['id'] = Variable<String>(id);
    map['baby'] = Variable<String>(baby);
    map['type'] = Variable<String>(type);
    map['ts'] = Variable<DateTime>(ts);
    map['data'] = Variable<String>(data);
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    return map;
  }

  RecordsCompanion toCompanion(bool nullToAbsent) {
    return RecordsCompanion(
      isDeleted: Value(isDeleted),
      clientUpdatedAt: clientUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      dirty: Value(dirty),
      id: Value(id),
      baby: Value(baby),
      type: Value(type),
      ts: Value(ts),
      data: Value(data),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
    );
  }

  factory RecordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecordRow(
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      clientUpdatedAt: serializer.fromJson<DateTime?>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      id: serializer.fromJson<String>(json['id']),
      baby: serializer.fromJson<String>(json['baby']),
      type: serializer.fromJson<String>(json['type']),
      ts: serializer.fromJson<DateTime>(json['ts']),
      data: serializer.fromJson<String>(json['data']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'clientUpdatedAt': serializer.toJson<DateTime?>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'id': serializer.toJson<String>(id),
      'baby': serializer.toJson<String>(baby),
      'type': serializer.toJson<String>(type),
      'ts': serializer.toJson<DateTime>(ts),
      'data': serializer.toJson<String>(data),
      'createdBy': serializer.toJson<String?>(createdBy),
    };
  }

  RecordRow copyWith({
    bool? isDeleted,
    Value<DateTime?> clientUpdatedAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    bool? dirty,
    String? id,
    String? baby,
    String? type,
    DateTime? ts,
    String? data,
    Value<String?> createdBy = const Value.absent(),
  }) => RecordRow(
    isDeleted: isDeleted ?? this.isDeleted,
    clientUpdatedAt: clientUpdatedAt.present
        ? clientUpdatedAt.value
        : this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    dirty: dirty ?? this.dirty,
    id: id ?? this.id,
    baby: baby ?? this.baby,
    type: type ?? this.type,
    ts: ts ?? this.ts,
    data: data ?? this.data,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
  );
  RecordRow copyWithCompanion(RecordsCompanion data) {
    return RecordRow(
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      id: data.id.present ? data.id.value : this.id,
      baby: data.baby.present ? data.baby.value : this.baby,
      type: data.type.present ? data.type.value : this.type,
      ts: data.ts.present ? data.ts.value : this.ts,
      data: data.data.present ? data.data.value : this.data,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecordRow(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('baby: $baby, ')
          ..write('type: $type, ')
          ..write('ts: $ts, ')
          ..write('data: $data, ')
          ..write('createdBy: $createdBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    baby,
    type,
    ts,
    data,
    createdBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecordRow &&
          other.isDeleted == this.isDeleted &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.dirty == this.dirty &&
          other.id == this.id &&
          other.baby == this.baby &&
          other.type == this.type &&
          other.ts == this.ts &&
          other.data == this.data &&
          other.createdBy == this.createdBy);
}

class RecordsCompanion extends UpdateCompanion<RecordRow> {
  final Value<bool> isDeleted;
  final Value<DateTime?> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<bool> dirty;
  final Value<String> id;
  final Value<String> baby;
  final Value<String> type;
  final Value<DateTime> ts;
  final Value<String> data;
  final Value<String?> createdBy;
  final Value<int> rowid;
  const RecordsCompanion({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.id = const Value.absent(),
    this.baby = const Value.absent(),
    this.type = const Value.absent(),
    this.ts = const Value.absent(),
    this.data = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordsCompanion.insert({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    required String id,
    required String baby,
    required String type,
    required DateTime ts,
    this.data = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       baby = Value(baby),
       type = Value(type),
       ts = Value(ts);
  static Insertable<RecordRow> custom({
    Expression<bool>? isDeleted,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<bool>? dirty,
    Expression<String>? id,
    Expression<String>? baby,
    Expression<String>? type,
    Expression<DateTime>? ts,
    Expression<String>? data,
    Expression<String>? createdBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (dirty != null) 'dirty': dirty,
      if (id != null) 'id': id,
      if (baby != null) 'baby': baby,
      if (type != null) 'type': type,
      if (ts != null) 'ts': ts,
      if (data != null) 'data': data,
      if (createdBy != null) 'created_by': createdBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordsCompanion copyWith({
    Value<bool>? isDeleted,
    Value<DateTime?>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<bool>? dirty,
    Value<String>? id,
    Value<String>? baby,
    Value<String>? type,
    Value<DateTime>? ts,
    Value<String>? data,
    Value<String?>? createdBy,
    Value<int>? rowid,
  }) {
    return RecordsCompanion(
      isDeleted: isDeleted ?? this.isDeleted,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      dirty: dirty ?? this.dirty,
      id: id ?? this.id,
      baby: baby ?? this.baby,
      type: type ?? this.type,
      ts: ts ?? this.ts,
      data: data ?? this.data,
      createdBy: createdBy ?? this.createdBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (baby.present) {
      map['baby'] = Variable<String>(baby.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (ts.present) {
      map['ts'] = Variable<DateTime>(ts.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordsCompanion(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('baby: $baby, ')
          ..write('type: $type, ')
          ..write('ts: $ts, ')
          ..write('data: $data, ')
          ..write('createdBy: $createdBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BabiesTable extends Babies with TableInfo<$BabiesTable, BabyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BabiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _photoMeta = const VerificationMeta('photo');
  @override
  late final GeneratedColumn<String> photo = GeneratedColumn<String>(
    'photo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('born'),
  );
  static const VerificationMeta _birthDateMeta = const VerificationMeta(
    'birthDate',
  );
  @override
  late final GeneratedColumn<DateTime> birthDate = GeneratedColumn<DateTime>(
    'birth_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMenstrualDateMeta = const VerificationMeta(
    'lastMenstrualDate',
  );
  @override
  late final GeneratedColumn<DateTime> lastMenstrualDate =
      GeneratedColumn<DateTime>(
        'last_menstrual_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _gestationalWeeksMeta = const VerificationMeta(
    'gestationalWeeks',
  );
  @override
  late final GeneratedColumn<int> gestationalWeeks = GeneratedColumn<int>(
    'gestational_weeks',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gestationalDaysMeta = const VerificationMeta(
    'gestationalDays',
  );
  @override
  late final GeneratedColumn<int> gestationalDays = GeneratedColumn<int>(
    'gestational_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _myRoleMeta = const VerificationMeta('myRole');
  @override
  late final GeneratedColumn<String> myRole = GeneratedColumn<String>(
    'my_role',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memberCountMeta = const VerificationMeta(
    'memberCount',
  );
  @override
  late final GeneratedColumn<int> memberCount = GeneratedColumn<int>(
    'member_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _settingsMeta = const VerificationMeta(
    'settings',
  );
  @override
  late final GeneratedColumn<String> settings = GeneratedColumn<String>(
    'settings',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    accountId,
    name,
    gender,
    photo,
    status,
    birthDate,
    dueDate,
    lastMenstrualDate,
    gestationalWeeks,
    gestationalDays,
    myRole,
    memberCount,
    settings,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'babies';
  @override
  VerificationContext validateIntegrity(
    Insertable<BabyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    }
    if (data.containsKey('photo')) {
      context.handle(
        _photoMeta,
        photo.isAcceptableOrUnknown(data['photo']!, _photoMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('birth_date')) {
      context.handle(
        _birthDateMeta,
        birthDate.isAcceptableOrUnknown(data['birth_date']!, _birthDateMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('last_menstrual_date')) {
      context.handle(
        _lastMenstrualDateMeta,
        lastMenstrualDate.isAcceptableOrUnknown(
          data['last_menstrual_date']!,
          _lastMenstrualDateMeta,
        ),
      );
    }
    if (data.containsKey('gestational_weeks')) {
      context.handle(
        _gestationalWeeksMeta,
        gestationalWeeks.isAcceptableOrUnknown(
          data['gestational_weeks']!,
          _gestationalWeeksMeta,
        ),
      );
    }
    if (data.containsKey('gestational_days')) {
      context.handle(
        _gestationalDaysMeta,
        gestationalDays.isAcceptableOrUnknown(
          data['gestational_days']!,
          _gestationalDaysMeta,
        ),
      );
    }
    if (data.containsKey('my_role')) {
      context.handle(
        _myRoleMeta,
        myRole.isAcceptableOrUnknown(data['my_role']!, _myRoleMeta),
      );
    }
    if (data.containsKey('member_count')) {
      context.handle(
        _memberCountMeta,
        memberCount.isAcceptableOrUnknown(
          data['member_count']!,
          _memberCountMeta,
        ),
      );
    }
    if (data.containsKey('settings')) {
      context.handle(
        _settingsMeta,
        settings.isAcceptableOrUnknown(data['settings']!, _settingsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BabyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BabyRow(
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      )!,
      photo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      birthDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}birth_date'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      lastMenstrualDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_menstrual_date'],
      ),
      gestationalWeeks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gestational_weeks'],
      ),
      gestationalDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gestational_days'],
      )!,
      myRole: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}my_role'],
      ),
      memberCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_count'],
      )!,
      settings: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settings'],
      )!,
    );
  }

  @override
  $BabiesTable createAlias(String alias) {
    return $BabiesTable(attachedDatabase, alias);
  }
}

class BabyRow extends DataClass implements Insertable<BabyRow> {
  final bool isDeleted;
  final DateTime? clientUpdatedAt;
  final DateTime? serverUpdatedAt;
  final bool dirty;
  final String id;
  final String? accountId;
  final String name;
  final String gender;
  final String? photo;
  final String status;
  final DateTime? birthDate;
  final DateTime? dueDate;
  final DateTime? lastMenstrualDate;
  final int? gestationalWeeks;
  final int gestationalDays;
  final String? myRole;
  final int memberCount;
  final String settings;
  const BabyRow({
    required this.isDeleted,
    this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.dirty,
    required this.id,
    this.accountId,
    required this.name,
    required this.gender,
    this.photo,
    required this.status,
    this.birthDate,
    this.dueDate,
    this.lastMenstrualDate,
    this.gestationalWeeks,
    required this.gestationalDays,
    this.myRole,
    required this.memberCount,
    required this.settings,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || clientUpdatedAt != null) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    map['name'] = Variable<String>(name);
    map['gender'] = Variable<String>(gender);
    if (!nullToAbsent || photo != null) {
      map['photo'] = Variable<String>(photo);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || birthDate != null) {
      map['birth_date'] = Variable<DateTime>(birthDate);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || lastMenstrualDate != null) {
      map['last_menstrual_date'] = Variable<DateTime>(lastMenstrualDate);
    }
    if (!nullToAbsent || gestationalWeeks != null) {
      map['gestational_weeks'] = Variable<int>(gestationalWeeks);
    }
    map['gestational_days'] = Variable<int>(gestationalDays);
    if (!nullToAbsent || myRole != null) {
      map['my_role'] = Variable<String>(myRole);
    }
    map['member_count'] = Variable<int>(memberCount);
    map['settings'] = Variable<String>(settings);
    return map;
  }

  BabiesCompanion toCompanion(bool nullToAbsent) {
    return BabiesCompanion(
      isDeleted: Value(isDeleted),
      clientUpdatedAt: clientUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      dirty: Value(dirty),
      id: Value(id),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      name: Value(name),
      gender: Value(gender),
      photo: photo == null && nullToAbsent
          ? const Value.absent()
          : Value(photo),
      status: Value(status),
      birthDate: birthDate == null && nullToAbsent
          ? const Value.absent()
          : Value(birthDate),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      lastMenstrualDate: lastMenstrualDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMenstrualDate),
      gestationalWeeks: gestationalWeeks == null && nullToAbsent
          ? const Value.absent()
          : Value(gestationalWeeks),
      gestationalDays: Value(gestationalDays),
      myRole: myRole == null && nullToAbsent
          ? const Value.absent()
          : Value(myRole),
      memberCount: Value(memberCount),
      settings: Value(settings),
    );
  }

  factory BabyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BabyRow(
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      clientUpdatedAt: serializer.fromJson<DateTime?>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      name: serializer.fromJson<String>(json['name']),
      gender: serializer.fromJson<String>(json['gender']),
      photo: serializer.fromJson<String?>(json['photo']),
      status: serializer.fromJson<String>(json['status']),
      birthDate: serializer.fromJson<DateTime?>(json['birthDate']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      lastMenstrualDate: serializer.fromJson<DateTime?>(
        json['lastMenstrualDate'],
      ),
      gestationalWeeks: serializer.fromJson<int?>(json['gestationalWeeks']),
      gestationalDays: serializer.fromJson<int>(json['gestationalDays']),
      myRole: serializer.fromJson<String?>(json['myRole']),
      memberCount: serializer.fromJson<int>(json['memberCount']),
      settings: serializer.fromJson<String>(json['settings']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'clientUpdatedAt': serializer.toJson<DateTime?>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String?>(accountId),
      'name': serializer.toJson<String>(name),
      'gender': serializer.toJson<String>(gender),
      'photo': serializer.toJson<String?>(photo),
      'status': serializer.toJson<String>(status),
      'birthDate': serializer.toJson<DateTime?>(birthDate),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'lastMenstrualDate': serializer.toJson<DateTime?>(lastMenstrualDate),
      'gestationalWeeks': serializer.toJson<int?>(gestationalWeeks),
      'gestationalDays': serializer.toJson<int>(gestationalDays),
      'myRole': serializer.toJson<String?>(myRole),
      'memberCount': serializer.toJson<int>(memberCount),
      'settings': serializer.toJson<String>(settings),
    };
  }

  BabyRow copyWith({
    bool? isDeleted,
    Value<DateTime?> clientUpdatedAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    bool? dirty,
    String? id,
    Value<String?> accountId = const Value.absent(),
    String? name,
    String? gender,
    Value<String?> photo = const Value.absent(),
    String? status,
    Value<DateTime?> birthDate = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    Value<DateTime?> lastMenstrualDate = const Value.absent(),
    Value<int?> gestationalWeeks = const Value.absent(),
    int? gestationalDays,
    Value<String?> myRole = const Value.absent(),
    int? memberCount,
    String? settings,
  }) => BabyRow(
    isDeleted: isDeleted ?? this.isDeleted,
    clientUpdatedAt: clientUpdatedAt.present
        ? clientUpdatedAt.value
        : this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    dirty: dirty ?? this.dirty,
    id: id ?? this.id,
    accountId: accountId.present ? accountId.value : this.accountId,
    name: name ?? this.name,
    gender: gender ?? this.gender,
    photo: photo.present ? photo.value : this.photo,
    status: status ?? this.status,
    birthDate: birthDate.present ? birthDate.value : this.birthDate,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    lastMenstrualDate: lastMenstrualDate.present
        ? lastMenstrualDate.value
        : this.lastMenstrualDate,
    gestationalWeeks: gestationalWeeks.present
        ? gestationalWeeks.value
        : this.gestationalWeeks,
    gestationalDays: gestationalDays ?? this.gestationalDays,
    myRole: myRole.present ? myRole.value : this.myRole,
    memberCount: memberCount ?? this.memberCount,
    settings: settings ?? this.settings,
  );
  BabyRow copyWithCompanion(BabiesCompanion data) {
    return BabyRow(
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      name: data.name.present ? data.name.value : this.name,
      gender: data.gender.present ? data.gender.value : this.gender,
      photo: data.photo.present ? data.photo.value : this.photo,
      status: data.status.present ? data.status.value : this.status,
      birthDate: data.birthDate.present ? data.birthDate.value : this.birthDate,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      lastMenstrualDate: data.lastMenstrualDate.present
          ? data.lastMenstrualDate.value
          : this.lastMenstrualDate,
      gestationalWeeks: data.gestationalWeeks.present
          ? data.gestationalWeeks.value
          : this.gestationalWeeks,
      gestationalDays: data.gestationalDays.present
          ? data.gestationalDays.value
          : this.gestationalDays,
      myRole: data.myRole.present ? data.myRole.value : this.myRole,
      memberCount: data.memberCount.present
          ? data.memberCount.value
          : this.memberCount,
      settings: data.settings.present ? data.settings.value : this.settings,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BabyRow(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('name: $name, ')
          ..write('gender: $gender, ')
          ..write('photo: $photo, ')
          ..write('status: $status, ')
          ..write('birthDate: $birthDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('lastMenstrualDate: $lastMenstrualDate, ')
          ..write('gestationalWeeks: $gestationalWeeks, ')
          ..write('gestationalDays: $gestationalDays, ')
          ..write('myRole: $myRole, ')
          ..write('memberCount: $memberCount, ')
          ..write('settings: $settings')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    accountId,
    name,
    gender,
    photo,
    status,
    birthDate,
    dueDate,
    lastMenstrualDate,
    gestationalWeeks,
    gestationalDays,
    myRole,
    memberCount,
    settings,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BabyRow &&
          other.isDeleted == this.isDeleted &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.dirty == this.dirty &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.name == this.name &&
          other.gender == this.gender &&
          other.photo == this.photo &&
          other.status == this.status &&
          other.birthDate == this.birthDate &&
          other.dueDate == this.dueDate &&
          other.lastMenstrualDate == this.lastMenstrualDate &&
          other.gestationalWeeks == this.gestationalWeeks &&
          other.gestationalDays == this.gestationalDays &&
          other.myRole == this.myRole &&
          other.memberCount == this.memberCount &&
          other.settings == this.settings);
}

class BabiesCompanion extends UpdateCompanion<BabyRow> {
  final Value<bool> isDeleted;
  final Value<DateTime?> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<bool> dirty;
  final Value<String> id;
  final Value<String?> accountId;
  final Value<String> name;
  final Value<String> gender;
  final Value<String?> photo;
  final Value<String> status;
  final Value<DateTime?> birthDate;
  final Value<DateTime?> dueDate;
  final Value<DateTime?> lastMenstrualDate;
  final Value<int?> gestationalWeeks;
  final Value<int> gestationalDays;
  final Value<String?> myRole;
  final Value<int> memberCount;
  final Value<String> settings;
  final Value<int> rowid;
  const BabiesCompanion({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.name = const Value.absent(),
    this.gender = const Value.absent(),
    this.photo = const Value.absent(),
    this.status = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.lastMenstrualDate = const Value.absent(),
    this.gestationalWeeks = const Value.absent(),
    this.gestationalDays = const Value.absent(),
    this.myRole = const Value.absent(),
    this.memberCount = const Value.absent(),
    this.settings = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BabiesCompanion.insert({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    required String id,
    this.accountId = const Value.absent(),
    required String name,
    this.gender = const Value.absent(),
    this.photo = const Value.absent(),
    this.status = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.lastMenstrualDate = const Value.absent(),
    this.gestationalWeeks = const Value.absent(),
    this.gestationalDays = const Value.absent(),
    this.myRole = const Value.absent(),
    this.memberCount = const Value.absent(),
    this.settings = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<BabyRow> custom({
    Expression<bool>? isDeleted,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<bool>? dirty,
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<String>? name,
    Expression<String>? gender,
    Expression<String>? photo,
    Expression<String>? status,
    Expression<DateTime>? birthDate,
    Expression<DateTime>? dueDate,
    Expression<DateTime>? lastMenstrualDate,
    Expression<int>? gestationalWeeks,
    Expression<int>? gestationalDays,
    Expression<String>? myRole,
    Expression<int>? memberCount,
    Expression<String>? settings,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (dirty != null) 'dirty': dirty,
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (name != null) 'name': name,
      if (gender != null) 'gender': gender,
      if (photo != null) 'photo': photo,
      if (status != null) 'status': status,
      if (birthDate != null) 'birth_date': birthDate,
      if (dueDate != null) 'due_date': dueDate,
      if (lastMenstrualDate != null) 'last_menstrual_date': lastMenstrualDate,
      if (gestationalWeeks != null) 'gestational_weeks': gestationalWeeks,
      if (gestationalDays != null) 'gestational_days': gestationalDays,
      if (myRole != null) 'my_role': myRole,
      if (memberCount != null) 'member_count': memberCount,
      if (settings != null) 'settings': settings,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BabiesCompanion copyWith({
    Value<bool>? isDeleted,
    Value<DateTime?>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<bool>? dirty,
    Value<String>? id,
    Value<String?>? accountId,
    Value<String>? name,
    Value<String>? gender,
    Value<String?>? photo,
    Value<String>? status,
    Value<DateTime?>? birthDate,
    Value<DateTime?>? dueDate,
    Value<DateTime?>? lastMenstrualDate,
    Value<int?>? gestationalWeeks,
    Value<int>? gestationalDays,
    Value<String?>? myRole,
    Value<int>? memberCount,
    Value<String>? settings,
    Value<int>? rowid,
  }) {
    return BabiesCompanion(
      isDeleted: isDeleted ?? this.isDeleted,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      dirty: dirty ?? this.dirty,
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      photo: photo ?? this.photo,
      status: status ?? this.status,
      birthDate: birthDate ?? this.birthDate,
      dueDate: dueDate ?? this.dueDate,
      lastMenstrualDate: lastMenstrualDate ?? this.lastMenstrualDate,
      gestationalWeeks: gestationalWeeks ?? this.gestationalWeeks,
      gestationalDays: gestationalDays ?? this.gestationalDays,
      myRole: myRole ?? this.myRole,
      memberCount: memberCount ?? this.memberCount,
      settings: settings ?? this.settings,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (photo.present) {
      map['photo'] = Variable<String>(photo.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (birthDate.present) {
      map['birth_date'] = Variable<DateTime>(birthDate.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (lastMenstrualDate.present) {
      map['last_menstrual_date'] = Variable<DateTime>(lastMenstrualDate.value);
    }
    if (gestationalWeeks.present) {
      map['gestational_weeks'] = Variable<int>(gestationalWeeks.value);
    }
    if (gestationalDays.present) {
      map['gestational_days'] = Variable<int>(gestationalDays.value);
    }
    if (myRole.present) {
      map['my_role'] = Variable<String>(myRole.value);
    }
    if (memberCount.present) {
      map['member_count'] = Variable<int>(memberCount.value);
    }
    if (settings.present) {
      map['settings'] = Variable<String>(settings.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BabiesCompanion(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('name: $name, ')
          ..write('gender: $gender, ')
          ..write('photo: $photo, ')
          ..write('status: $status, ')
          ..write('birthDate: $birthDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('lastMenstrualDate: $lastMenstrualDate, ')
          ..write('gestationalWeeks: $gestationalWeeks, ')
          ..write('gestationalDays: $gestationalDays, ')
          ..write('myRole: $myRole, ')
          ..write('memberCount: $memberCount, ')
          ..write('settings: $settings, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoriesTable extends Memories
    with TableInfo<$MemoriesTable, MemoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _babyMeta = const VerificationMeta('baby');
  @override
  late final GeneratedColumn<String> baby = GeneratedColumn<String>(
    'baby',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _photoMeta = const VerificationMeta('photo');
  @override
  late final GeneratedColumn<String> photo = GeneratedColumn<String>(
    'photo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localPhotoPathMeta = const VerificationMeta(
    'localPhotoPath',
  );
  @override
  late final GeneratedColumn<String> localPhotoPath = GeneratedColumn<String>(
    'local_photo_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstTagMeta = const VerificationMeta(
    'firstTag',
  );
  @override
  late final GeneratedColumn<String> firstTag = GeneratedColumn<String>(
    'first_tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    baby,
    date,
    title,
    note,
    photo,
    localPhotoPath,
    firstTag,
    createdBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memories';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('baby')) {
      context.handle(
        _babyMeta,
        baby.isAcceptableOrUnknown(data['baby']!, _babyMeta),
      );
    } else if (isInserting) {
      context.missing(_babyMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('photo')) {
      context.handle(
        _photoMeta,
        photo.isAcceptableOrUnknown(data['photo']!, _photoMeta),
      );
    }
    if (data.containsKey('local_photo_path')) {
      context.handle(
        _localPhotoPathMeta,
        localPhotoPath.isAcceptableOrUnknown(
          data['local_photo_path']!,
          _localPhotoPathMeta,
        ),
      );
    }
    if (data.containsKey('first_tag')) {
      context.handle(
        _firstTagMeta,
        firstTag.isAcceptableOrUnknown(data['first_tag']!, _firstTagMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MemoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoryRow(
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      baby: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baby'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      photo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo'],
      ),
      localPhotoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_photo_path'],
      ),
      firstTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_tag'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
    );
  }

  @override
  $MemoriesTable createAlias(String alias) {
    return $MemoriesTable(attachedDatabase, alias);
  }
}

class MemoryRow extends DataClass implements Insertable<MemoryRow> {
  final bool isDeleted;
  final DateTime? clientUpdatedAt;
  final DateTime? serverUpdatedAt;
  final bool dirty;
  final String id;
  final String baby;
  final DateTime date;
  final String title;
  final String note;
  final String? photo;
  final String? localPhotoPath;
  final String firstTag;
  final String? createdBy;
  const MemoryRow({
    required this.isDeleted,
    this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.dirty,
    required this.id,
    required this.baby,
    required this.date,
    required this.title,
    required this.note,
    this.photo,
    this.localPhotoPath,
    required this.firstTag,
    this.createdBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || clientUpdatedAt != null) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['id'] = Variable<String>(id);
    map['baby'] = Variable<String>(baby);
    map['date'] = Variable<DateTime>(date);
    map['title'] = Variable<String>(title);
    map['note'] = Variable<String>(note);
    if (!nullToAbsent || photo != null) {
      map['photo'] = Variable<String>(photo);
    }
    if (!nullToAbsent || localPhotoPath != null) {
      map['local_photo_path'] = Variable<String>(localPhotoPath);
    }
    map['first_tag'] = Variable<String>(firstTag);
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    return map;
  }

  MemoriesCompanion toCompanion(bool nullToAbsent) {
    return MemoriesCompanion(
      isDeleted: Value(isDeleted),
      clientUpdatedAt: clientUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      dirty: Value(dirty),
      id: Value(id),
      baby: Value(baby),
      date: Value(date),
      title: Value(title),
      note: Value(note),
      photo: photo == null && nullToAbsent
          ? const Value.absent()
          : Value(photo),
      localPhotoPath: localPhotoPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPhotoPath),
      firstTag: Value(firstTag),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
    );
  }

  factory MemoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoryRow(
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      clientUpdatedAt: serializer.fromJson<DateTime?>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      id: serializer.fromJson<String>(json['id']),
      baby: serializer.fromJson<String>(json['baby']),
      date: serializer.fromJson<DateTime>(json['date']),
      title: serializer.fromJson<String>(json['title']),
      note: serializer.fromJson<String>(json['note']),
      photo: serializer.fromJson<String?>(json['photo']),
      localPhotoPath: serializer.fromJson<String?>(json['localPhotoPath']),
      firstTag: serializer.fromJson<String>(json['firstTag']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'clientUpdatedAt': serializer.toJson<DateTime?>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'id': serializer.toJson<String>(id),
      'baby': serializer.toJson<String>(baby),
      'date': serializer.toJson<DateTime>(date),
      'title': serializer.toJson<String>(title),
      'note': serializer.toJson<String>(note),
      'photo': serializer.toJson<String?>(photo),
      'localPhotoPath': serializer.toJson<String?>(localPhotoPath),
      'firstTag': serializer.toJson<String>(firstTag),
      'createdBy': serializer.toJson<String?>(createdBy),
    };
  }

  MemoryRow copyWith({
    bool? isDeleted,
    Value<DateTime?> clientUpdatedAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    bool? dirty,
    String? id,
    String? baby,
    DateTime? date,
    String? title,
    String? note,
    Value<String?> photo = const Value.absent(),
    Value<String?> localPhotoPath = const Value.absent(),
    String? firstTag,
    Value<String?> createdBy = const Value.absent(),
  }) => MemoryRow(
    isDeleted: isDeleted ?? this.isDeleted,
    clientUpdatedAt: clientUpdatedAt.present
        ? clientUpdatedAt.value
        : this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    dirty: dirty ?? this.dirty,
    id: id ?? this.id,
    baby: baby ?? this.baby,
    date: date ?? this.date,
    title: title ?? this.title,
    note: note ?? this.note,
    photo: photo.present ? photo.value : this.photo,
    localPhotoPath: localPhotoPath.present
        ? localPhotoPath.value
        : this.localPhotoPath,
    firstTag: firstTag ?? this.firstTag,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
  );
  MemoryRow copyWithCompanion(MemoriesCompanion data) {
    return MemoryRow(
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      id: data.id.present ? data.id.value : this.id,
      baby: data.baby.present ? data.baby.value : this.baby,
      date: data.date.present ? data.date.value : this.date,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      photo: data.photo.present ? data.photo.value : this.photo,
      localPhotoPath: data.localPhotoPath.present
          ? data.localPhotoPath.value
          : this.localPhotoPath,
      firstTag: data.firstTag.present ? data.firstTag.value : this.firstTag,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoryRow(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('baby: $baby, ')
          ..write('date: $date, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('photo: $photo, ')
          ..write('localPhotoPath: $localPhotoPath, ')
          ..write('firstTag: $firstTag, ')
          ..write('createdBy: $createdBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    baby,
    date,
    title,
    note,
    photo,
    localPhotoPath,
    firstTag,
    createdBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryRow &&
          other.isDeleted == this.isDeleted &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.dirty == this.dirty &&
          other.id == this.id &&
          other.baby == this.baby &&
          other.date == this.date &&
          other.title == this.title &&
          other.note == this.note &&
          other.photo == this.photo &&
          other.localPhotoPath == this.localPhotoPath &&
          other.firstTag == this.firstTag &&
          other.createdBy == this.createdBy);
}

class MemoriesCompanion extends UpdateCompanion<MemoryRow> {
  final Value<bool> isDeleted;
  final Value<DateTime?> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<bool> dirty;
  final Value<String> id;
  final Value<String> baby;
  final Value<DateTime> date;
  final Value<String> title;
  final Value<String> note;
  final Value<String?> photo;
  final Value<String?> localPhotoPath;
  final Value<String> firstTag;
  final Value<String?> createdBy;
  final Value<int> rowid;
  const MemoriesCompanion({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.id = const Value.absent(),
    this.baby = const Value.absent(),
    this.date = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.photo = const Value.absent(),
    this.localPhotoPath = const Value.absent(),
    this.firstTag = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoriesCompanion.insert({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    required String id,
    required String baby,
    required DateTime date,
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.photo = const Value.absent(),
    this.localPhotoPath = const Value.absent(),
    this.firstTag = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       baby = Value(baby),
       date = Value(date);
  static Insertable<MemoryRow> custom({
    Expression<bool>? isDeleted,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<bool>? dirty,
    Expression<String>? id,
    Expression<String>? baby,
    Expression<DateTime>? date,
    Expression<String>? title,
    Expression<String>? note,
    Expression<String>? photo,
    Expression<String>? localPhotoPath,
    Expression<String>? firstTag,
    Expression<String>? createdBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (dirty != null) 'dirty': dirty,
      if (id != null) 'id': id,
      if (baby != null) 'baby': baby,
      if (date != null) 'date': date,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (photo != null) 'photo': photo,
      if (localPhotoPath != null) 'local_photo_path': localPhotoPath,
      if (firstTag != null) 'first_tag': firstTag,
      if (createdBy != null) 'created_by': createdBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoriesCompanion copyWith({
    Value<bool>? isDeleted,
    Value<DateTime?>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<bool>? dirty,
    Value<String>? id,
    Value<String>? baby,
    Value<DateTime>? date,
    Value<String>? title,
    Value<String>? note,
    Value<String?>? photo,
    Value<String?>? localPhotoPath,
    Value<String>? firstTag,
    Value<String?>? createdBy,
    Value<int>? rowid,
  }) {
    return MemoriesCompanion(
      isDeleted: isDeleted ?? this.isDeleted,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      dirty: dirty ?? this.dirty,
      id: id ?? this.id,
      baby: baby ?? this.baby,
      date: date ?? this.date,
      title: title ?? this.title,
      note: note ?? this.note,
      photo: photo ?? this.photo,
      localPhotoPath: localPhotoPath ?? this.localPhotoPath,
      firstTag: firstTag ?? this.firstTag,
      createdBy: createdBy ?? this.createdBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (baby.present) {
      map['baby'] = Variable<String>(baby.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (photo.present) {
      map['photo'] = Variable<String>(photo.value);
    }
    if (localPhotoPath.present) {
      map['local_photo_path'] = Variable<String>(localPhotoPath.value);
    }
    if (firstTag.present) {
      map['first_tag'] = Variable<String>(firstTag.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoriesCompanion(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('baby: $baby, ')
          ..write('date: $date, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('photo: $photo, ')
          ..write('localPhotoPath: $localPhotoPath, ')
          ..write('firstTag: $firstTag, ')
          ..write('createdBy: $createdBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MomEntriesTable extends MomEntries
    with TableInfo<$MomEntriesTable, MomEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MomEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _babyMeta = const VerificationMeta('baby');
  @override
  late final GeneratedColumn<String> baby = GeneratedColumn<String>(
    'baby',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightKgMeta = const VerificationMeta(
    'weightKg',
  );
  @override
  late final GeneratedColumn<double> weightKg = GeneratedColumn<double>(
    'weight_kg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    baby,
    kind,
    date,
    weightKg,
    title,
    note,
    createdBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mom_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<MomEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('baby')) {
      context.handle(
        _babyMeta,
        baby.isAcceptableOrUnknown(data['baby']!, _babyMeta),
      );
    } else if (isInserting) {
      context.missing(_babyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('weight_kg')) {
      context.handle(
        _weightKgMeta,
        weightKg.isAcceptableOrUnknown(data['weight_kg']!, _weightKgMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MomEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MomEntryRow(
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      baby: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baby'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      weightKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight_kg'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
    );
  }

  @override
  $MomEntriesTable createAlias(String alias) {
    return $MomEntriesTable(attachedDatabase, alias);
  }
}

class MomEntryRow extends DataClass implements Insertable<MomEntryRow> {
  final bool isDeleted;
  final DateTime? clientUpdatedAt;
  final DateTime? serverUpdatedAt;
  final bool dirty;
  final String id;
  final String baby;
  final String kind;
  final DateTime date;
  final double? weightKg;
  final String? title;
  final String? note;
  final String? createdBy;
  const MomEntryRow({
    required this.isDeleted,
    this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.dirty,
    required this.id,
    required this.baby,
    required this.kind,
    required this.date,
    this.weightKg,
    this.title,
    this.note,
    this.createdBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || clientUpdatedAt != null) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['id'] = Variable<String>(id);
    map['baby'] = Variable<String>(baby);
    map['kind'] = Variable<String>(kind);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || weightKg != null) {
      map['weight_kg'] = Variable<double>(weightKg);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    return map;
  }

  MomEntriesCompanion toCompanion(bool nullToAbsent) {
    return MomEntriesCompanion(
      isDeleted: Value(isDeleted),
      clientUpdatedAt: clientUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      dirty: Value(dirty),
      id: Value(id),
      baby: Value(baby),
      kind: Value(kind),
      date: Value(date),
      weightKg: weightKg == null && nullToAbsent
          ? const Value.absent()
          : Value(weightKg),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
    );
  }

  factory MomEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MomEntryRow(
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      clientUpdatedAt: serializer.fromJson<DateTime?>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      id: serializer.fromJson<String>(json['id']),
      baby: serializer.fromJson<String>(json['baby']),
      kind: serializer.fromJson<String>(json['kind']),
      date: serializer.fromJson<DateTime>(json['date']),
      weightKg: serializer.fromJson<double?>(json['weightKg']),
      title: serializer.fromJson<String?>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'clientUpdatedAt': serializer.toJson<DateTime?>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'id': serializer.toJson<String>(id),
      'baby': serializer.toJson<String>(baby),
      'kind': serializer.toJson<String>(kind),
      'date': serializer.toJson<DateTime>(date),
      'weightKg': serializer.toJson<double?>(weightKg),
      'title': serializer.toJson<String?>(title),
      'note': serializer.toJson<String?>(note),
      'createdBy': serializer.toJson<String?>(createdBy),
    };
  }

  MomEntryRow copyWith({
    bool? isDeleted,
    Value<DateTime?> clientUpdatedAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    bool? dirty,
    String? id,
    String? baby,
    String? kind,
    DateTime? date,
    Value<double?> weightKg = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<String?> createdBy = const Value.absent(),
  }) => MomEntryRow(
    isDeleted: isDeleted ?? this.isDeleted,
    clientUpdatedAt: clientUpdatedAt.present
        ? clientUpdatedAt.value
        : this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    dirty: dirty ?? this.dirty,
    id: id ?? this.id,
    baby: baby ?? this.baby,
    kind: kind ?? this.kind,
    date: date ?? this.date,
    weightKg: weightKg.present ? weightKg.value : this.weightKg,
    title: title.present ? title.value : this.title,
    note: note.present ? note.value : this.note,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
  );
  MomEntryRow copyWithCompanion(MomEntriesCompanion data) {
    return MomEntryRow(
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      id: data.id.present ? data.id.value : this.id,
      baby: data.baby.present ? data.baby.value : this.baby,
      kind: data.kind.present ? data.kind.value : this.kind,
      date: data.date.present ? data.date.value : this.date,
      weightKg: data.weightKg.present ? data.weightKg.value : this.weightKg,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MomEntryRow(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('baby: $baby, ')
          ..write('kind: $kind, ')
          ..write('date: $date, ')
          ..write('weightKg: $weightKg, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('createdBy: $createdBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    baby,
    kind,
    date,
    weightKg,
    title,
    note,
    createdBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MomEntryRow &&
          other.isDeleted == this.isDeleted &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.dirty == this.dirty &&
          other.id == this.id &&
          other.baby == this.baby &&
          other.kind == this.kind &&
          other.date == this.date &&
          other.weightKg == this.weightKg &&
          other.title == this.title &&
          other.note == this.note &&
          other.createdBy == this.createdBy);
}

class MomEntriesCompanion extends UpdateCompanion<MomEntryRow> {
  final Value<bool> isDeleted;
  final Value<DateTime?> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<bool> dirty;
  final Value<String> id;
  final Value<String> baby;
  final Value<String> kind;
  final Value<DateTime> date;
  final Value<double?> weightKg;
  final Value<String?> title;
  final Value<String?> note;
  final Value<String?> createdBy;
  final Value<int> rowid;
  const MomEntriesCompanion({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.id = const Value.absent(),
    this.baby = const Value.absent(),
    this.kind = const Value.absent(),
    this.date = const Value.absent(),
    this.weightKg = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MomEntriesCompanion.insert({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    required String id,
    required String baby,
    required String kind,
    required DateTime date,
    this.weightKg = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       baby = Value(baby),
       kind = Value(kind),
       date = Value(date);
  static Insertable<MomEntryRow> custom({
    Expression<bool>? isDeleted,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<bool>? dirty,
    Expression<String>? id,
    Expression<String>? baby,
    Expression<String>? kind,
    Expression<DateTime>? date,
    Expression<double>? weightKg,
    Expression<String>? title,
    Expression<String>? note,
    Expression<String>? createdBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (dirty != null) 'dirty': dirty,
      if (id != null) 'id': id,
      if (baby != null) 'baby': baby,
      if (kind != null) 'kind': kind,
      if (date != null) 'date': date,
      if (weightKg != null) 'weight_kg': weightKg,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (createdBy != null) 'created_by': createdBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MomEntriesCompanion copyWith({
    Value<bool>? isDeleted,
    Value<DateTime?>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<bool>? dirty,
    Value<String>? id,
    Value<String>? baby,
    Value<String>? kind,
    Value<DateTime>? date,
    Value<double?>? weightKg,
    Value<String?>? title,
    Value<String?>? note,
    Value<String?>? createdBy,
    Value<int>? rowid,
  }) {
    return MomEntriesCompanion(
      isDeleted: isDeleted ?? this.isDeleted,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      dirty: dirty ?? this.dirty,
      id: id ?? this.id,
      baby: baby ?? this.baby,
      kind: kind ?? this.kind,
      date: date ?? this.date,
      weightKg: weightKg ?? this.weightKg,
      title: title ?? this.title,
      note: note ?? this.note,
      createdBy: createdBy ?? this.createdBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (baby.present) {
      map['baby'] = Variable<String>(baby.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (weightKg.present) {
      map['weight_kg'] = Variable<double>(weightKg.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MomEntriesCompanion(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('baby: $baby, ')
          ..write('kind: $kind, ')
          ..write('date: $date, ')
          ..write('weightKg: $weightKg, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('createdBy: $createdBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CycleSettingsTableTable extends CycleSettingsTable
    with TableInfo<$CycleSettingsTableTable, CycleSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CycleSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('me'),
  );
  static const VerificationMeta _babyMeta = const VerificationMeta('baby');
  @override
  late final GeneratedColumn<String> baby = GeneratedColumn<String>(
    'baby',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _birthDateMeta = const VerificationMeta(
    'birthDate',
  );
  @override
  late final GeneratedColumn<DateTime> birthDate = GeneratedColumn<DateTime>(
    'birth_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _breastfeedingMeta = const VerificationMeta(
    'breastfeeding',
  );
  @override
  late final GeneratedColumn<String> breastfeeding = GeneratedColumn<String>(
    'breastfeeding',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstPeriodDateMeta = const VerificationMeta(
    'firstPeriodDate',
  );
  @override
  late final GeneratedColumn<DateTime> firstPeriodDate =
      GeneratedColumn<DateTime>(
        'first_period_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remindersMeta = const VerificationMeta(
    'reminders',
  );
  @override
  late final GeneratedColumn<String> reminders = GeneratedColumn<String>(
    'reminders',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _showFertilityWarningMeta =
      const VerificationMeta('showFertilityWarning');
  @override
  late final GeneratedColumn<bool> showFertilityWarning = GeneratedColumn<bool>(
    'show_fertility_warning',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("show_fertility_warning" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _expectedCycleLengthMeta =
      const VerificationMeta('expectedCycleLength');
  @override
  late final GeneratedColumn<int> expectedCycleLength = GeneratedColumn<int>(
    'expected_cycle_length',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _periodLengthMeta = const VerificationMeta(
    'periodLength',
  );
  @override
  late final GeneratedColumn<int> periodLength = GeneratedColumn<int>(
    'period_length',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lutealPhaseLengthMeta = const VerificationMeta(
    'lutealPhaseLength',
  );
  @override
  late final GeneratedColumn<int> lutealPhaseLength = GeneratedColumn<int>(
    'luteal_phase_length',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smartPredictionMeta = const VerificationMeta(
    'smartPrediction',
  );
  @override
  late final GeneratedColumn<bool> smartPrediction = GeneratedColumn<bool>(
    'smart_prediction',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("smart_prediction" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _weekStartsSundayMeta = const VerificationMeta(
    'weekStartsSunday',
  );
  @override
  late final GeneratedColumn<bool> weekStartsSunday = GeneratedColumn<bool>(
    'week_starts_sunday',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("week_starts_sunday" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    baby,
    birthDate,
    breastfeeding,
    firstPeriodDate,
    reminders,
    showFertilityWarning,
    enabled,
    expectedCycleLength,
    periodLength,
    lutealPhaseLength,
    smartPrediction,
    weekStartsSunday,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cycle_settings_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<CycleSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('baby')) {
      context.handle(
        _babyMeta,
        baby.isAcceptableOrUnknown(data['baby']!, _babyMeta),
      );
    }
    if (data.containsKey('birth_date')) {
      context.handle(
        _birthDateMeta,
        birthDate.isAcceptableOrUnknown(data['birth_date']!, _birthDateMeta),
      );
    }
    if (data.containsKey('breastfeeding')) {
      context.handle(
        _breastfeedingMeta,
        breastfeeding.isAcceptableOrUnknown(
          data['breastfeeding']!,
          _breastfeedingMeta,
        ),
      );
    }
    if (data.containsKey('first_period_date')) {
      context.handle(
        _firstPeriodDateMeta,
        firstPeriodDate.isAcceptableOrUnknown(
          data['first_period_date']!,
          _firstPeriodDateMeta,
        ),
      );
    }
    if (data.containsKey('reminders')) {
      context.handle(
        _remindersMeta,
        reminders.isAcceptableOrUnknown(data['reminders']!, _remindersMeta),
      );
    }
    if (data.containsKey('show_fertility_warning')) {
      context.handle(
        _showFertilityWarningMeta,
        showFertilityWarning.isAcceptableOrUnknown(
          data['show_fertility_warning']!,
          _showFertilityWarningMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('expected_cycle_length')) {
      context.handle(
        _expectedCycleLengthMeta,
        expectedCycleLength.isAcceptableOrUnknown(
          data['expected_cycle_length']!,
          _expectedCycleLengthMeta,
        ),
      );
    }
    if (data.containsKey('period_length')) {
      context.handle(
        _periodLengthMeta,
        periodLength.isAcceptableOrUnknown(
          data['period_length']!,
          _periodLengthMeta,
        ),
      );
    }
    if (data.containsKey('luteal_phase_length')) {
      context.handle(
        _lutealPhaseLengthMeta,
        lutealPhaseLength.isAcceptableOrUnknown(
          data['luteal_phase_length']!,
          _lutealPhaseLengthMeta,
        ),
      );
    }
    if (data.containsKey('smart_prediction')) {
      context.handle(
        _smartPredictionMeta,
        smartPrediction.isAcceptableOrUnknown(
          data['smart_prediction']!,
          _smartPredictionMeta,
        ),
      );
    }
    if (data.containsKey('week_starts_sunday')) {
      context.handle(
        _weekStartsSundayMeta,
        weekStartsSunday.isAcceptableOrUnknown(
          data['week_starts_sunday']!,
          _weekStartsSundayMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CycleSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CycleSettingsRow(
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      baby: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baby'],
      ),
      birthDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}birth_date'],
      ),
      breastfeeding: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}breastfeeding'],
      ),
      firstPeriodDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_period_date'],
      ),
      reminders: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reminders'],
      )!,
      showFertilityWarning: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}show_fertility_warning'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      expectedCycleLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_cycle_length'],
      ),
      periodLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}period_length'],
      ),
      lutealPhaseLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}luteal_phase_length'],
      ),
      smartPrediction: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}smart_prediction'],
      )!,
      weekStartsSunday: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}week_starts_sunday'],
      )!,
    );
  }

  @override
  $CycleSettingsTableTable createAlias(String alias) {
    return $CycleSettingsTableTable(attachedDatabase, alias);
  }
}

class CycleSettingsRow extends DataClass
    implements Insertable<CycleSettingsRow> {
  final bool isDeleted;
  final DateTime? clientUpdatedAt;
  final DateTime? serverUpdatedAt;
  final bool dirty;
  final String id;
  final String? baby;
  final DateTime? birthDate;
  final String? breastfeeding;
  final DateTime? firstPeriodDate;
  final String reminders;
  final bool showFertilityWarning;
  final bool enabled;
  final int? expectedCycleLength;
  final int? periodLength;
  final int? lutealPhaseLength;
  final bool smartPrediction;
  final bool weekStartsSunday;
  const CycleSettingsRow({
    required this.isDeleted,
    this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.dirty,
    required this.id,
    this.baby,
    this.birthDate,
    this.breastfeeding,
    this.firstPeriodDate,
    required this.reminders,
    required this.showFertilityWarning,
    required this.enabled,
    this.expectedCycleLength,
    this.periodLength,
    this.lutealPhaseLength,
    required this.smartPrediction,
    required this.weekStartsSunday,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || clientUpdatedAt != null) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || baby != null) {
      map['baby'] = Variable<String>(baby);
    }
    if (!nullToAbsent || birthDate != null) {
      map['birth_date'] = Variable<DateTime>(birthDate);
    }
    if (!nullToAbsent || breastfeeding != null) {
      map['breastfeeding'] = Variable<String>(breastfeeding);
    }
    if (!nullToAbsent || firstPeriodDate != null) {
      map['first_period_date'] = Variable<DateTime>(firstPeriodDate);
    }
    map['reminders'] = Variable<String>(reminders);
    map['show_fertility_warning'] = Variable<bool>(showFertilityWarning);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || expectedCycleLength != null) {
      map['expected_cycle_length'] = Variable<int>(expectedCycleLength);
    }
    if (!nullToAbsent || periodLength != null) {
      map['period_length'] = Variable<int>(periodLength);
    }
    if (!nullToAbsent || lutealPhaseLength != null) {
      map['luteal_phase_length'] = Variable<int>(lutealPhaseLength);
    }
    map['smart_prediction'] = Variable<bool>(smartPrediction);
    map['week_starts_sunday'] = Variable<bool>(weekStartsSunday);
    return map;
  }

  CycleSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return CycleSettingsTableCompanion(
      isDeleted: Value(isDeleted),
      clientUpdatedAt: clientUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      dirty: Value(dirty),
      id: Value(id),
      baby: baby == null && nullToAbsent ? const Value.absent() : Value(baby),
      birthDate: birthDate == null && nullToAbsent
          ? const Value.absent()
          : Value(birthDate),
      breastfeeding: breastfeeding == null && nullToAbsent
          ? const Value.absent()
          : Value(breastfeeding),
      firstPeriodDate: firstPeriodDate == null && nullToAbsent
          ? const Value.absent()
          : Value(firstPeriodDate),
      reminders: Value(reminders),
      showFertilityWarning: Value(showFertilityWarning),
      enabled: Value(enabled),
      expectedCycleLength: expectedCycleLength == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedCycleLength),
      periodLength: periodLength == null && nullToAbsent
          ? const Value.absent()
          : Value(periodLength),
      lutealPhaseLength: lutealPhaseLength == null && nullToAbsent
          ? const Value.absent()
          : Value(lutealPhaseLength),
      smartPrediction: Value(smartPrediction),
      weekStartsSunday: Value(weekStartsSunday),
    );
  }

  factory CycleSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CycleSettingsRow(
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      clientUpdatedAt: serializer.fromJson<DateTime?>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      id: serializer.fromJson<String>(json['id']),
      baby: serializer.fromJson<String?>(json['baby']),
      birthDate: serializer.fromJson<DateTime?>(json['birthDate']),
      breastfeeding: serializer.fromJson<String?>(json['breastfeeding']),
      firstPeriodDate: serializer.fromJson<DateTime?>(json['firstPeriodDate']),
      reminders: serializer.fromJson<String>(json['reminders']),
      showFertilityWarning: serializer.fromJson<bool>(
        json['showFertilityWarning'],
      ),
      enabled: serializer.fromJson<bool>(json['enabled']),
      expectedCycleLength: serializer.fromJson<int?>(
        json['expectedCycleLength'],
      ),
      periodLength: serializer.fromJson<int?>(json['periodLength']),
      lutealPhaseLength: serializer.fromJson<int?>(json['lutealPhaseLength']),
      smartPrediction: serializer.fromJson<bool>(json['smartPrediction']),
      weekStartsSunday: serializer.fromJson<bool>(json['weekStartsSunday']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'clientUpdatedAt': serializer.toJson<DateTime?>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'id': serializer.toJson<String>(id),
      'baby': serializer.toJson<String?>(baby),
      'birthDate': serializer.toJson<DateTime?>(birthDate),
      'breastfeeding': serializer.toJson<String?>(breastfeeding),
      'firstPeriodDate': serializer.toJson<DateTime?>(firstPeriodDate),
      'reminders': serializer.toJson<String>(reminders),
      'showFertilityWarning': serializer.toJson<bool>(showFertilityWarning),
      'enabled': serializer.toJson<bool>(enabled),
      'expectedCycleLength': serializer.toJson<int?>(expectedCycleLength),
      'periodLength': serializer.toJson<int?>(periodLength),
      'lutealPhaseLength': serializer.toJson<int?>(lutealPhaseLength),
      'smartPrediction': serializer.toJson<bool>(smartPrediction),
      'weekStartsSunday': serializer.toJson<bool>(weekStartsSunday),
    };
  }

  CycleSettingsRow copyWith({
    bool? isDeleted,
    Value<DateTime?> clientUpdatedAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    bool? dirty,
    String? id,
    Value<String?> baby = const Value.absent(),
    Value<DateTime?> birthDate = const Value.absent(),
    Value<String?> breastfeeding = const Value.absent(),
    Value<DateTime?> firstPeriodDate = const Value.absent(),
    String? reminders,
    bool? showFertilityWarning,
    bool? enabled,
    Value<int?> expectedCycleLength = const Value.absent(),
    Value<int?> periodLength = const Value.absent(),
    Value<int?> lutealPhaseLength = const Value.absent(),
    bool? smartPrediction,
    bool? weekStartsSunday,
  }) => CycleSettingsRow(
    isDeleted: isDeleted ?? this.isDeleted,
    clientUpdatedAt: clientUpdatedAt.present
        ? clientUpdatedAt.value
        : this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    dirty: dirty ?? this.dirty,
    id: id ?? this.id,
    baby: baby.present ? baby.value : this.baby,
    birthDate: birthDate.present ? birthDate.value : this.birthDate,
    breastfeeding: breastfeeding.present
        ? breastfeeding.value
        : this.breastfeeding,
    firstPeriodDate: firstPeriodDate.present
        ? firstPeriodDate.value
        : this.firstPeriodDate,
    reminders: reminders ?? this.reminders,
    showFertilityWarning: showFertilityWarning ?? this.showFertilityWarning,
    enabled: enabled ?? this.enabled,
    expectedCycleLength: expectedCycleLength.present
        ? expectedCycleLength.value
        : this.expectedCycleLength,
    periodLength: periodLength.present ? periodLength.value : this.periodLength,
    lutealPhaseLength: lutealPhaseLength.present
        ? lutealPhaseLength.value
        : this.lutealPhaseLength,
    smartPrediction: smartPrediction ?? this.smartPrediction,
    weekStartsSunday: weekStartsSunday ?? this.weekStartsSunday,
  );
  CycleSettingsRow copyWithCompanion(CycleSettingsTableCompanion data) {
    return CycleSettingsRow(
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      id: data.id.present ? data.id.value : this.id,
      baby: data.baby.present ? data.baby.value : this.baby,
      birthDate: data.birthDate.present ? data.birthDate.value : this.birthDate,
      breastfeeding: data.breastfeeding.present
          ? data.breastfeeding.value
          : this.breastfeeding,
      firstPeriodDate: data.firstPeriodDate.present
          ? data.firstPeriodDate.value
          : this.firstPeriodDate,
      reminders: data.reminders.present ? data.reminders.value : this.reminders,
      showFertilityWarning: data.showFertilityWarning.present
          ? data.showFertilityWarning.value
          : this.showFertilityWarning,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      expectedCycleLength: data.expectedCycleLength.present
          ? data.expectedCycleLength.value
          : this.expectedCycleLength,
      periodLength: data.periodLength.present
          ? data.periodLength.value
          : this.periodLength,
      lutealPhaseLength: data.lutealPhaseLength.present
          ? data.lutealPhaseLength.value
          : this.lutealPhaseLength,
      smartPrediction: data.smartPrediction.present
          ? data.smartPrediction.value
          : this.smartPrediction,
      weekStartsSunday: data.weekStartsSunday.present
          ? data.weekStartsSunday.value
          : this.weekStartsSunday,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CycleSettingsRow(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('baby: $baby, ')
          ..write('birthDate: $birthDate, ')
          ..write('breastfeeding: $breastfeeding, ')
          ..write('firstPeriodDate: $firstPeriodDate, ')
          ..write('reminders: $reminders, ')
          ..write('showFertilityWarning: $showFertilityWarning, ')
          ..write('enabled: $enabled, ')
          ..write('expectedCycleLength: $expectedCycleLength, ')
          ..write('periodLength: $periodLength, ')
          ..write('lutealPhaseLength: $lutealPhaseLength, ')
          ..write('smartPrediction: $smartPrediction, ')
          ..write('weekStartsSunday: $weekStartsSunday')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    baby,
    birthDate,
    breastfeeding,
    firstPeriodDate,
    reminders,
    showFertilityWarning,
    enabled,
    expectedCycleLength,
    periodLength,
    lutealPhaseLength,
    smartPrediction,
    weekStartsSunday,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CycleSettingsRow &&
          other.isDeleted == this.isDeleted &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.dirty == this.dirty &&
          other.id == this.id &&
          other.baby == this.baby &&
          other.birthDate == this.birthDate &&
          other.breastfeeding == this.breastfeeding &&
          other.firstPeriodDate == this.firstPeriodDate &&
          other.reminders == this.reminders &&
          other.showFertilityWarning == this.showFertilityWarning &&
          other.enabled == this.enabled &&
          other.expectedCycleLength == this.expectedCycleLength &&
          other.periodLength == this.periodLength &&
          other.lutealPhaseLength == this.lutealPhaseLength &&
          other.smartPrediction == this.smartPrediction &&
          other.weekStartsSunday == this.weekStartsSunday);
}

class CycleSettingsTableCompanion extends UpdateCompanion<CycleSettingsRow> {
  final Value<bool> isDeleted;
  final Value<DateTime?> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<bool> dirty;
  final Value<String> id;
  final Value<String?> baby;
  final Value<DateTime?> birthDate;
  final Value<String?> breastfeeding;
  final Value<DateTime?> firstPeriodDate;
  final Value<String> reminders;
  final Value<bool> showFertilityWarning;
  final Value<bool> enabled;
  final Value<int?> expectedCycleLength;
  final Value<int?> periodLength;
  final Value<int?> lutealPhaseLength;
  final Value<bool> smartPrediction;
  final Value<bool> weekStartsSunday;
  final Value<int> rowid;
  const CycleSettingsTableCompanion({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.id = const Value.absent(),
    this.baby = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.breastfeeding = const Value.absent(),
    this.firstPeriodDate = const Value.absent(),
    this.reminders = const Value.absent(),
    this.showFertilityWarning = const Value.absent(),
    this.enabled = const Value.absent(),
    this.expectedCycleLength = const Value.absent(),
    this.periodLength = const Value.absent(),
    this.lutealPhaseLength = const Value.absent(),
    this.smartPrediction = const Value.absent(),
    this.weekStartsSunday = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CycleSettingsTableCompanion.insert({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.id = const Value.absent(),
    this.baby = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.breastfeeding = const Value.absent(),
    this.firstPeriodDate = const Value.absent(),
    this.reminders = const Value.absent(),
    this.showFertilityWarning = const Value.absent(),
    this.enabled = const Value.absent(),
    this.expectedCycleLength = const Value.absent(),
    this.periodLength = const Value.absent(),
    this.lutealPhaseLength = const Value.absent(),
    this.smartPrediction = const Value.absent(),
    this.weekStartsSunday = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  static Insertable<CycleSettingsRow> custom({
    Expression<bool>? isDeleted,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<bool>? dirty,
    Expression<String>? id,
    Expression<String>? baby,
    Expression<DateTime>? birthDate,
    Expression<String>? breastfeeding,
    Expression<DateTime>? firstPeriodDate,
    Expression<String>? reminders,
    Expression<bool>? showFertilityWarning,
    Expression<bool>? enabled,
    Expression<int>? expectedCycleLength,
    Expression<int>? periodLength,
    Expression<int>? lutealPhaseLength,
    Expression<bool>? smartPrediction,
    Expression<bool>? weekStartsSunday,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (dirty != null) 'dirty': dirty,
      if (id != null) 'id': id,
      if (baby != null) 'baby': baby,
      if (birthDate != null) 'birth_date': birthDate,
      if (breastfeeding != null) 'breastfeeding': breastfeeding,
      if (firstPeriodDate != null) 'first_period_date': firstPeriodDate,
      if (reminders != null) 'reminders': reminders,
      if (showFertilityWarning != null)
        'show_fertility_warning': showFertilityWarning,
      if (enabled != null) 'enabled': enabled,
      if (expectedCycleLength != null)
        'expected_cycle_length': expectedCycleLength,
      if (periodLength != null) 'period_length': periodLength,
      if (lutealPhaseLength != null) 'luteal_phase_length': lutealPhaseLength,
      if (smartPrediction != null) 'smart_prediction': smartPrediction,
      if (weekStartsSunday != null) 'week_starts_sunday': weekStartsSunday,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CycleSettingsTableCompanion copyWith({
    Value<bool>? isDeleted,
    Value<DateTime?>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<bool>? dirty,
    Value<String>? id,
    Value<String?>? baby,
    Value<DateTime?>? birthDate,
    Value<String?>? breastfeeding,
    Value<DateTime?>? firstPeriodDate,
    Value<String>? reminders,
    Value<bool>? showFertilityWarning,
    Value<bool>? enabled,
    Value<int?>? expectedCycleLength,
    Value<int?>? periodLength,
    Value<int?>? lutealPhaseLength,
    Value<bool>? smartPrediction,
    Value<bool>? weekStartsSunday,
    Value<int>? rowid,
  }) {
    return CycleSettingsTableCompanion(
      isDeleted: isDeleted ?? this.isDeleted,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      dirty: dirty ?? this.dirty,
      id: id ?? this.id,
      baby: baby ?? this.baby,
      birthDate: birthDate ?? this.birthDate,
      breastfeeding: breastfeeding ?? this.breastfeeding,
      firstPeriodDate: firstPeriodDate ?? this.firstPeriodDate,
      reminders: reminders ?? this.reminders,
      showFertilityWarning: showFertilityWarning ?? this.showFertilityWarning,
      enabled: enabled ?? this.enabled,
      expectedCycleLength: expectedCycleLength ?? this.expectedCycleLength,
      periodLength: periodLength ?? this.periodLength,
      lutealPhaseLength: lutealPhaseLength ?? this.lutealPhaseLength,
      smartPrediction: smartPrediction ?? this.smartPrediction,
      weekStartsSunday: weekStartsSunday ?? this.weekStartsSunday,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (baby.present) {
      map['baby'] = Variable<String>(baby.value);
    }
    if (birthDate.present) {
      map['birth_date'] = Variable<DateTime>(birthDate.value);
    }
    if (breastfeeding.present) {
      map['breastfeeding'] = Variable<String>(breastfeeding.value);
    }
    if (firstPeriodDate.present) {
      map['first_period_date'] = Variable<DateTime>(firstPeriodDate.value);
    }
    if (reminders.present) {
      map['reminders'] = Variable<String>(reminders.value);
    }
    if (showFertilityWarning.present) {
      map['show_fertility_warning'] = Variable<bool>(
        showFertilityWarning.value,
      );
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (expectedCycleLength.present) {
      map['expected_cycle_length'] = Variable<int>(expectedCycleLength.value);
    }
    if (periodLength.present) {
      map['period_length'] = Variable<int>(periodLength.value);
    }
    if (lutealPhaseLength.present) {
      map['luteal_phase_length'] = Variable<int>(lutealPhaseLength.value);
    }
    if (smartPrediction.present) {
      map['smart_prediction'] = Variable<bool>(smartPrediction.value);
    }
    if (weekStartsSunday.present) {
      map['week_starts_sunday'] = Variable<bool>(weekStartsSunday.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CycleSettingsTableCompanion(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('baby: $baby, ')
          ..write('birthDate: $birthDate, ')
          ..write('breastfeeding: $breastfeeding, ')
          ..write('firstPeriodDate: $firstPeriodDate, ')
          ..write('reminders: $reminders, ')
          ..write('showFertilityWarning: $showFertilityWarning, ')
          ..write('enabled: $enabled, ')
          ..write('expectedCycleLength: $expectedCycleLength, ')
          ..write('periodLength: $periodLength, ')
          ..write('lutealPhaseLength: $lutealPhaseLength, ')
          ..write('smartPrediction: $smartPrediction, ')
          ..write('weekStartsSunday: $weekStartsSunday, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CycleEntriesTable extends CycleEntries
    with TableInfo<$CycleEntriesTable, CycleEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CycleEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _flowMeta = const VerificationMeta('flow');
  @override
  late final GeneratedColumn<String> flow = GeneratedColumn<String>(
    'flow',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lochiaColorMeta = const VerificationMeta(
    'lochiaColor',
  );
  @override
  late final GeneratedColumn<String> lochiaColor = GeneratedColumn<String>(
    'lochia_color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _symptomsMeta = const VerificationMeta(
    'symptoms',
  );
  @override
  late final GeneratedColumn<String> symptoms = GeneratedColumn<String>(
    'symptoms',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<int> mood = GeneratedColumn<int>(
    'mood',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    accountId,
    date,
    flow,
    lochiaColor,
    symptoms,
    mood,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cycle_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CycleEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('flow')) {
      context.handle(
        _flowMeta,
        flow.isAcceptableOrUnknown(data['flow']!, _flowMeta),
      );
    }
    if (data.containsKey('lochia_color')) {
      context.handle(
        _lochiaColorMeta,
        lochiaColor.isAcceptableOrUnknown(
          data['lochia_color']!,
          _lochiaColorMeta,
        ),
      );
    }
    if (data.containsKey('symptoms')) {
      context.handle(
        _symptomsMeta,
        symptoms.isAcceptableOrUnknown(data['symptoms']!, _symptomsMeta),
      );
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CycleEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CycleEntryRow(
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      ),
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      flow: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}flow'],
      ),
      lochiaColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lochia_color'],
      ),
      symptoms: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symptoms'],
      )!,
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mood'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $CycleEntriesTable createAlias(String alias) {
    return $CycleEntriesTable(attachedDatabase, alias);
  }
}

class CycleEntryRow extends DataClass implements Insertable<CycleEntryRow> {
  final bool isDeleted;
  final DateTime? clientUpdatedAt;
  final DateTime? serverUpdatedAt;
  final bool dirty;
  final String id;
  final String? accountId;
  final DateTime date;
  final String? flow;
  final String? lochiaColor;
  final String symptoms;
  final int? mood;
  final String? note;
  const CycleEntryRow({
    required this.isDeleted,
    this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.dirty,
    required this.id,
    this.accountId,
    required this.date,
    this.flow,
    this.lochiaColor,
    required this.symptoms,
    this.mood,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['is_deleted'] = Variable<bool>(isDeleted);
    if (!nullToAbsent || clientUpdatedAt != null) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    }
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['dirty'] = Variable<bool>(dirty);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || flow != null) {
      map['flow'] = Variable<String>(flow);
    }
    if (!nullToAbsent || lochiaColor != null) {
      map['lochia_color'] = Variable<String>(lochiaColor);
    }
    map['symptoms'] = Variable<String>(symptoms);
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<int>(mood);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  CycleEntriesCompanion toCompanion(bool nullToAbsent) {
    return CycleEntriesCompanion(
      isDeleted: Value(isDeleted),
      clientUpdatedAt: clientUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      dirty: Value(dirty),
      id: Value(id),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      date: Value(date),
      flow: flow == null && nullToAbsent ? const Value.absent() : Value(flow),
      lochiaColor: lochiaColor == null && nullToAbsent
          ? const Value.absent()
          : Value(lochiaColor),
      symptoms: Value(symptoms),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory CycleEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CycleEntryRow(
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      clientUpdatedAt: serializer.fromJson<DateTime?>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      id: serializer.fromJson<String>(json['id']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      date: serializer.fromJson<DateTime>(json['date']),
      flow: serializer.fromJson<String?>(json['flow']),
      lochiaColor: serializer.fromJson<String?>(json['lochiaColor']),
      symptoms: serializer.fromJson<String>(json['symptoms']),
      mood: serializer.fromJson<int?>(json['mood']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'clientUpdatedAt': serializer.toJson<DateTime?>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'id': serializer.toJson<String>(id),
      'accountId': serializer.toJson<String?>(accountId),
      'date': serializer.toJson<DateTime>(date),
      'flow': serializer.toJson<String?>(flow),
      'lochiaColor': serializer.toJson<String?>(lochiaColor),
      'symptoms': serializer.toJson<String>(symptoms),
      'mood': serializer.toJson<int?>(mood),
      'note': serializer.toJson<String?>(note),
    };
  }

  CycleEntryRow copyWith({
    bool? isDeleted,
    Value<DateTime?> clientUpdatedAt = const Value.absent(),
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    bool? dirty,
    String? id,
    Value<String?> accountId = const Value.absent(),
    DateTime? date,
    Value<String?> flow = const Value.absent(),
    Value<String?> lochiaColor = const Value.absent(),
    String? symptoms,
    Value<int?> mood = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) => CycleEntryRow(
    isDeleted: isDeleted ?? this.isDeleted,
    clientUpdatedAt: clientUpdatedAt.present
        ? clientUpdatedAt.value
        : this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    dirty: dirty ?? this.dirty,
    id: id ?? this.id,
    accountId: accountId.present ? accountId.value : this.accountId,
    date: date ?? this.date,
    flow: flow.present ? flow.value : this.flow,
    lochiaColor: lochiaColor.present ? lochiaColor.value : this.lochiaColor,
    symptoms: symptoms ?? this.symptoms,
    mood: mood.present ? mood.value : this.mood,
    note: note.present ? note.value : this.note,
  );
  CycleEntryRow copyWithCompanion(CycleEntriesCompanion data) {
    return CycleEntryRow(
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      date: data.date.present ? data.date.value : this.date,
      flow: data.flow.present ? data.flow.value : this.flow,
      lochiaColor: data.lochiaColor.present
          ? data.lochiaColor.value
          : this.lochiaColor,
      symptoms: data.symptoms.present ? data.symptoms.value : this.symptoms,
      mood: data.mood.present ? data.mood.value : this.mood,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CycleEntryRow(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('date: $date, ')
          ..write('flow: $flow, ')
          ..write('lochiaColor: $lochiaColor, ')
          ..write('symptoms: $symptoms, ')
          ..write('mood: $mood, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    isDeleted,
    clientUpdatedAt,
    serverUpdatedAt,
    dirty,
    id,
    accountId,
    date,
    flow,
    lochiaColor,
    symptoms,
    mood,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CycleEntryRow &&
          other.isDeleted == this.isDeleted &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.dirty == this.dirty &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.date == this.date &&
          other.flow == this.flow &&
          other.lochiaColor == this.lochiaColor &&
          other.symptoms == this.symptoms &&
          other.mood == this.mood &&
          other.note == this.note);
}

class CycleEntriesCompanion extends UpdateCompanion<CycleEntryRow> {
  final Value<bool> isDeleted;
  final Value<DateTime?> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<bool> dirty;
  final Value<String> id;
  final Value<String?> accountId;
  final Value<DateTime> date;
  final Value<String?> flow;
  final Value<String?> lochiaColor;
  final Value<String> symptoms;
  final Value<int?> mood;
  final Value<String?> note;
  final Value<int> rowid;
  const CycleEntriesCompanion({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.date = const Value.absent(),
    this.flow = const Value.absent(),
    this.lochiaColor = const Value.absent(),
    this.symptoms = const Value.absent(),
    this.mood = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CycleEntriesCompanion.insert({
    this.isDeleted = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    required String id,
    this.accountId = const Value.absent(),
    required DateTime date,
    this.flow = const Value.absent(),
    this.lochiaColor = const Value.absent(),
    this.symptoms = const Value.absent(),
    this.mood = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       date = Value(date);
  static Insertable<CycleEntryRow> custom({
    Expression<bool>? isDeleted,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<bool>? dirty,
    Expression<String>? id,
    Expression<String>? accountId,
    Expression<DateTime>? date,
    Expression<String>? flow,
    Expression<String>? lochiaColor,
    Expression<String>? symptoms,
    Expression<int>? mood,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (dirty != null) 'dirty': dirty,
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (date != null) 'date': date,
      if (flow != null) 'flow': flow,
      if (lochiaColor != null) 'lochia_color': lochiaColor,
      if (symptoms != null) 'symptoms': symptoms,
      if (mood != null) 'mood': mood,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CycleEntriesCompanion copyWith({
    Value<bool>? isDeleted,
    Value<DateTime?>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<bool>? dirty,
    Value<String>? id,
    Value<String?>? accountId,
    Value<DateTime>? date,
    Value<String?>? flow,
    Value<String?>? lochiaColor,
    Value<String>? symptoms,
    Value<int?>? mood,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return CycleEntriesCompanion(
      isDeleted: isDeleted ?? this.isDeleted,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      dirty: dirty ?? this.dirty,
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      date: date ?? this.date,
      flow: flow ?? this.flow,
      lochiaColor: lochiaColor ?? this.lochiaColor,
      symptoms: symptoms ?? this.symptoms,
      mood: mood ?? this.mood,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (flow.present) {
      map['flow'] = Variable<String>(flow.value);
    }
    if (lochiaColor.present) {
      map['lochia_color'] = Variable<String>(lochiaColor.value);
    }
    if (symptoms.present) {
      map['symptoms'] = Variable<String>(symptoms.value);
    }
    if (mood.present) {
      map['mood'] = Variable<int>(mood.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CycleEntriesCompanion(')
          ..write('isDeleted: $isDeleted, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('date: $date, ')
          ..write('flow: $flow, ')
          ..write('lochiaColor: $lochiaColor, ')
          ..write('symptoms: $symptoms, ')
          ..write('mood: $mood, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, SyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _babyMeta = const VerificationMeta('baby');
  @override
  late final GeneratedColumn<String> baby = GeneratedColumn<String>(
    'baby',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
    'cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [baby, cursor];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('baby')) {
      context.handle(
        _babyMeta,
        baby.isAcceptableOrUnknown(data['baby']!, _babyMeta),
      );
    } else if (isInserting) {
      context.missing(_babyMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {baby};
  @override
  SyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursor(
      baby: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baby'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cursor'],
      ),
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class SyncCursor extends DataClass implements Insertable<SyncCursor> {
  final String baby;
  final String? cursor;
  const SyncCursor({required this.baby, this.cursor});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['baby'] = Variable<String>(baby);
    if (!nullToAbsent || cursor != null) {
      map['cursor'] = Variable<String>(cursor);
    }
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      baby: Value(baby),
      cursor: cursor == null && nullToAbsent
          ? const Value.absent()
          : Value(cursor),
    );
  }

  factory SyncCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursor(
      baby: serializer.fromJson<String>(json['baby']),
      cursor: serializer.fromJson<String?>(json['cursor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'baby': serializer.toJson<String>(baby),
      'cursor': serializer.toJson<String?>(cursor),
    };
  }

  SyncCursor copyWith({
    String? baby,
    Value<String?> cursor = const Value.absent(),
  }) => SyncCursor(
    baby: baby ?? this.baby,
    cursor: cursor.present ? cursor.value : this.cursor,
  );
  SyncCursor copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursor(
      baby: data.baby.present ? data.baby.value : this.baby,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursor(')
          ..write('baby: $baby, ')
          ..write('cursor: $cursor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(baby, cursor);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursor &&
          other.baby == this.baby &&
          other.cursor == this.cursor);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursor> {
  final Value<String> baby;
  final Value<String?> cursor;
  final Value<int> rowid;
  const SyncCursorsCompanion({
    this.baby = const Value.absent(),
    this.cursor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String baby,
    this.cursor = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : baby = Value(baby);
  static Insertable<SyncCursor> custom({
    Expression<String>? baby,
    Expression<String>? cursor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (baby != null) 'baby': baby,
      if (cursor != null) 'cursor': cursor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<String>? baby,
    Value<String?>? cursor,
    Value<int>? rowid,
  }) {
    return SyncCursorsCompanion(
      baby: baby ?? this.baby,
      cursor: cursor ?? this.cursor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (baby.present) {
      map['baby'] = Variable<String>(baby.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('baby: $baby, ')
          ..write('cursor: $cursor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HealthStatusesTable extends HealthStatuses
    with TableInfo<$HealthStatusesTable, HealthStatusRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HealthStatusesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _babyMeta = const VerificationMeta('baby');
  @override
  late final GeneratedColumn<String> baby = GeneratedColumn<String>(
    'baby',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemKeyMeta = const VerificationMeta(
    'itemKey',
  );
  @override
  late final GeneratedColumn<String> itemKey = GeneratedColumn<String>(
    'item_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<bool> done = GeneratedColumn<bool>(
    'done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("done" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _statusDateMeta = const VerificationMeta(
    'statusDate',
  );
  @override
  late final GeneratedColumn<DateTime> statusDate = GeneratedColumn<DateTime>(
    'status_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [baby, kind, itemKey, done, statusDate];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'health_statuses';
  @override
  VerificationContext validateIntegrity(
    Insertable<HealthStatusRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('baby')) {
      context.handle(
        _babyMeta,
        baby.isAcceptableOrUnknown(data['baby']!, _babyMeta),
      );
    } else if (isInserting) {
      context.missing(_babyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('item_key')) {
      context.handle(
        _itemKeyMeta,
        itemKey.isAcceptableOrUnknown(data['item_key']!, _itemKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_itemKeyMeta);
    }
    if (data.containsKey('done')) {
      context.handle(
        _doneMeta,
        done.isAcceptableOrUnknown(data['done']!, _doneMeta),
      );
    }
    if (data.containsKey('status_date')) {
      context.handle(
        _statusDateMeta,
        statusDate.isAcceptableOrUnknown(data['status_date']!, _statusDateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {baby, kind, itemKey};
  @override
  HealthStatusRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HealthStatusRow(
      baby: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baby'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      itemKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_key'],
      )!,
      done: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}done'],
      )!,
      statusDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}status_date'],
      ),
    );
  }

  @override
  $HealthStatusesTable createAlias(String alias) {
    return $HealthStatusesTable(attachedDatabase, alias);
  }
}

class HealthStatusRow extends DataClass implements Insertable<HealthStatusRow> {
  final String baby;
  final String kind;
  final String itemKey;
  final bool done;
  final DateTime? statusDate;
  const HealthStatusRow({
    required this.baby,
    required this.kind,
    required this.itemKey,
    required this.done,
    this.statusDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['baby'] = Variable<String>(baby);
    map['kind'] = Variable<String>(kind);
    map['item_key'] = Variable<String>(itemKey);
    map['done'] = Variable<bool>(done);
    if (!nullToAbsent || statusDate != null) {
      map['status_date'] = Variable<DateTime>(statusDate);
    }
    return map;
  }

  HealthStatusesCompanion toCompanion(bool nullToAbsent) {
    return HealthStatusesCompanion(
      baby: Value(baby),
      kind: Value(kind),
      itemKey: Value(itemKey),
      done: Value(done),
      statusDate: statusDate == null && nullToAbsent
          ? const Value.absent()
          : Value(statusDate),
    );
  }

  factory HealthStatusRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HealthStatusRow(
      baby: serializer.fromJson<String>(json['baby']),
      kind: serializer.fromJson<String>(json['kind']),
      itemKey: serializer.fromJson<String>(json['itemKey']),
      done: serializer.fromJson<bool>(json['done']),
      statusDate: serializer.fromJson<DateTime?>(json['statusDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'baby': serializer.toJson<String>(baby),
      'kind': serializer.toJson<String>(kind),
      'itemKey': serializer.toJson<String>(itemKey),
      'done': serializer.toJson<bool>(done),
      'statusDate': serializer.toJson<DateTime?>(statusDate),
    };
  }

  HealthStatusRow copyWith({
    String? baby,
    String? kind,
    String? itemKey,
    bool? done,
    Value<DateTime?> statusDate = const Value.absent(),
  }) => HealthStatusRow(
    baby: baby ?? this.baby,
    kind: kind ?? this.kind,
    itemKey: itemKey ?? this.itemKey,
    done: done ?? this.done,
    statusDate: statusDate.present ? statusDate.value : this.statusDate,
  );
  HealthStatusRow copyWithCompanion(HealthStatusesCompanion data) {
    return HealthStatusRow(
      baby: data.baby.present ? data.baby.value : this.baby,
      kind: data.kind.present ? data.kind.value : this.kind,
      itemKey: data.itemKey.present ? data.itemKey.value : this.itemKey,
      done: data.done.present ? data.done.value : this.done,
      statusDate: data.statusDate.present
          ? data.statusDate.value
          : this.statusDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HealthStatusRow(')
          ..write('baby: $baby, ')
          ..write('kind: $kind, ')
          ..write('itemKey: $itemKey, ')
          ..write('done: $done, ')
          ..write('statusDate: $statusDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(baby, kind, itemKey, done, statusDate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HealthStatusRow &&
          other.baby == this.baby &&
          other.kind == this.kind &&
          other.itemKey == this.itemKey &&
          other.done == this.done &&
          other.statusDate == this.statusDate);
}

class HealthStatusesCompanion extends UpdateCompanion<HealthStatusRow> {
  final Value<String> baby;
  final Value<String> kind;
  final Value<String> itemKey;
  final Value<bool> done;
  final Value<DateTime?> statusDate;
  final Value<int> rowid;
  const HealthStatusesCompanion({
    this.baby = const Value.absent(),
    this.kind = const Value.absent(),
    this.itemKey = const Value.absent(),
    this.done = const Value.absent(),
    this.statusDate = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HealthStatusesCompanion.insert({
    required String baby,
    required String kind,
    required String itemKey,
    this.done = const Value.absent(),
    this.statusDate = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : baby = Value(baby),
       kind = Value(kind),
       itemKey = Value(itemKey);
  static Insertable<HealthStatusRow> custom({
    Expression<String>? baby,
    Expression<String>? kind,
    Expression<String>? itemKey,
    Expression<bool>? done,
    Expression<DateTime>? statusDate,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (baby != null) 'baby': baby,
      if (kind != null) 'kind': kind,
      if (itemKey != null) 'item_key': itemKey,
      if (done != null) 'done': done,
      if (statusDate != null) 'status_date': statusDate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HealthStatusesCompanion copyWith({
    Value<String>? baby,
    Value<String>? kind,
    Value<String>? itemKey,
    Value<bool>? done,
    Value<DateTime?>? statusDate,
    Value<int>? rowid,
  }) {
    return HealthStatusesCompanion(
      baby: baby ?? this.baby,
      kind: kind ?? this.kind,
      itemKey: itemKey ?? this.itemKey,
      done: done ?? this.done,
      statusDate: statusDate ?? this.statusDate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (baby.present) {
      map['baby'] = Variable<String>(baby.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (itemKey.present) {
      map['item_key'] = Variable<String>(itemKey.value);
    }
    if (done.present) {
      map['done'] = Variable<bool>(done.value);
    }
    if (statusDate.present) {
      map['status_date'] = Variable<DateTime>(statusDate.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HealthStatusesCompanion(')
          ..write('baby: $baby, ')
          ..write('kind: $kind, ')
          ..write('itemKey: $itemKey, ')
          ..write('done: $done, ')
          ..write('statusDate: $statusDate, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalRemindersTable extends LocalReminders
    with TableInfo<$LocalRemindersTable, ReminderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRemindersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<int> localId = GeneratedColumn<int>(
    'local_id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _babyMeta = const VerificationMeta('baby');
  @override
  late final GeneratedColumn<String> baby = GeneratedColumn<String>(
    'baby',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('custom'),
  );
  static const VerificationMeta _scheduleJsonMeta = const VerificationMeta(
    'scheduleJson',
  );
  @override
  late final GeneratedColumn<String> scheduleJson = GeneratedColumn<String>(
    'schedule_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    baby,
    type,
    scheduleJson,
    enabled,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_reminders';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReminderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    }
    if (data.containsKey('baby')) {
      context.handle(
        _babyMeta,
        baby.isAcceptableOrUnknown(data['baby']!, _babyMeta),
      );
    } else if (isInserting) {
      context.missing(_babyMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('schedule_json')) {
      context.handle(
        _scheduleJsonMeta,
        scheduleJson.isAcceptableOrUnknown(
          data['schedule_json']!,
          _scheduleJsonMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  ReminderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReminderRow(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_id'],
      )!,
      baby: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baby'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      scheduleJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_json'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
    );
  }

  @override
  $LocalRemindersTable createAlias(String alias) {
    return $LocalRemindersTable(attachedDatabase, alias);
  }
}

class ReminderRow extends DataClass implements Insertable<ReminderRow> {
  final int localId;
  final String baby;
  final String type;
  final String scheduleJson;
  final bool enabled;
  final DateTime? createdAt;
  const ReminderRow({
    required this.localId,
    required this.baby,
    required this.type,
    required this.scheduleJson,
    required this.enabled,
    this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<int>(localId);
    map['baby'] = Variable<String>(baby);
    map['type'] = Variable<String>(type);
    map['schedule_json'] = Variable<String>(scheduleJson);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    return map;
  }

  LocalRemindersCompanion toCompanion(bool nullToAbsent) {
    return LocalRemindersCompanion(
      localId: Value(localId),
      baby: Value(baby),
      type: Value(type),
      scheduleJson: Value(scheduleJson),
      enabled: Value(enabled),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
    );
  }

  factory ReminderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReminderRow(
      localId: serializer.fromJson<int>(json['localId']),
      baby: serializer.fromJson<String>(json['baby']),
      type: serializer.fromJson<String>(json['type']),
      scheduleJson: serializer.fromJson<String>(json['scheduleJson']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<int>(localId),
      'baby': serializer.toJson<String>(baby),
      'type': serializer.toJson<String>(type),
      'scheduleJson': serializer.toJson<String>(scheduleJson),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
    };
  }

  ReminderRow copyWith({
    int? localId,
    String? baby,
    String? type,
    String? scheduleJson,
    bool? enabled,
    Value<DateTime?> createdAt = const Value.absent(),
  }) => ReminderRow(
    localId: localId ?? this.localId,
    baby: baby ?? this.baby,
    type: type ?? this.type,
    scheduleJson: scheduleJson ?? this.scheduleJson,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
  );
  ReminderRow copyWithCompanion(LocalRemindersCompanion data) {
    return ReminderRow(
      localId: data.localId.present ? data.localId.value : this.localId,
      baby: data.baby.present ? data.baby.value : this.baby,
      type: data.type.present ? data.type.value : this.type,
      scheduleJson: data.scheduleJson.present
          ? data.scheduleJson.value
          : this.scheduleJson,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReminderRow(')
          ..write('localId: $localId, ')
          ..write('baby: $baby, ')
          ..write('type: $type, ')
          ..write('scheduleJson: $scheduleJson, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(localId, baby, type, scheduleJson, enabled, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReminderRow &&
          other.localId == this.localId &&
          other.baby == this.baby &&
          other.type == this.type &&
          other.scheduleJson == this.scheduleJson &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt);
}

class LocalRemindersCompanion extends UpdateCompanion<ReminderRow> {
  final Value<int> localId;
  final Value<String> baby;
  final Value<String> type;
  final Value<String> scheduleJson;
  final Value<bool> enabled;
  final Value<DateTime?> createdAt;
  const LocalRemindersCompanion({
    this.localId = const Value.absent(),
    this.baby = const Value.absent(),
    this.type = const Value.absent(),
    this.scheduleJson = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  LocalRemindersCompanion.insert({
    this.localId = const Value.absent(),
    required String baby,
    this.type = const Value.absent(),
    this.scheduleJson = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : baby = Value(baby);
  static Insertable<ReminderRow> custom({
    Expression<int>? localId,
    Expression<String>? baby,
    Expression<String>? type,
    Expression<String>? scheduleJson,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (baby != null) 'baby': baby,
      if (type != null) 'type': type,
      if (scheduleJson != null) 'schedule_json': scheduleJson,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  LocalRemindersCompanion copyWith({
    Value<int>? localId,
    Value<String>? baby,
    Value<String>? type,
    Value<String>? scheduleJson,
    Value<bool>? enabled,
    Value<DateTime?>? createdAt,
  }) {
    return LocalRemindersCompanion(
      localId: localId ?? this.localId,
      baby: baby ?? this.baby,
      type: type ?? this.type,
      scheduleJson: scheduleJson ?? this.scheduleJson,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<int>(localId.value);
    }
    if (baby.present) {
      map['baby'] = Variable<String>(baby.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (scheduleJson.present) {
      map['schedule_json'] = Variable<String>(scheduleJson.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalRemindersCompanion(')
          ..write('localId: $localId, ')
          ..write('baby: $baby, ')
          ..write('type: $type, ')
          ..write('scheduleJson: $scheduleJson, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $RecordsTable records = $RecordsTable(this);
  late final $BabiesTable babies = $BabiesTable(this);
  late final $MemoriesTable memories = $MemoriesTable(this);
  late final $MomEntriesTable momEntries = $MomEntriesTable(this);
  late final $CycleSettingsTableTable cycleSettingsTable =
      $CycleSettingsTableTable(this);
  late final $CycleEntriesTable cycleEntries = $CycleEntriesTable(this);
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $HealthStatusesTable healthStatuses = $HealthStatusesTable(this);
  late final $LocalRemindersTable localReminders = $LocalRemindersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    records,
    babies,
    memories,
    momEntries,
    cycleSettingsTable,
    cycleEntries,
    syncCursors,
    healthStatuses,
    localReminders,
  ];
}

typedef $$RecordsTableCreateCompanionBuilder =
    RecordsCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      required String id,
      required String baby,
      required String type,
      required DateTime ts,
      Value<String> data,
      Value<String?> createdBy,
      Value<int> rowid,
    });
typedef $$RecordsTableUpdateCompanionBuilder =
    RecordsCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      Value<String> id,
      Value<String> baby,
      Value<String> type,
      Value<DateTime> ts,
      Value<String> data,
      Value<String?> createdBy,
      Value<int> rowid,
    });

class $$RecordsTableFilterComposer
    extends Composer<_$AppDatabase, $RecordsTable> {
  $$RecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $RecordsTable> {
  $$RecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecordsTable> {
  $$RecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baby =>
      $composableBuilder(column: $table.baby, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);
}

class $$RecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecordsTable,
          RecordRow,
          $$RecordsTableFilterComposer,
          $$RecordsTableOrderingComposer,
          $$RecordsTableAnnotationComposer,
          $$RecordsTableCreateCompanionBuilder,
          $$RecordsTableUpdateCompanionBuilder,
          (RecordRow, BaseReferences<_$AppDatabase, $RecordsTable, RecordRow>),
          RecordRow,
          PrefetchHooks Function()
        > {
  $$RecordsTableTableManager(_$AppDatabase db, $RecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> baby = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<DateTime> ts = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordsCompanion(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                baby: baby,
                type: type,
                ts: ts,
                data: data,
                createdBy: createdBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                required String id,
                required String baby,
                required String type,
                required DateTime ts,
                Value<String> data = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordsCompanion.insert(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                baby: baby,
                type: type,
                ts: ts,
                data: data,
                createdBy: createdBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecordsTable,
      RecordRow,
      $$RecordsTableFilterComposer,
      $$RecordsTableOrderingComposer,
      $$RecordsTableAnnotationComposer,
      $$RecordsTableCreateCompanionBuilder,
      $$RecordsTableUpdateCompanionBuilder,
      (RecordRow, BaseReferences<_$AppDatabase, $RecordsTable, RecordRow>),
      RecordRow,
      PrefetchHooks Function()
    >;
typedef $$BabiesTableCreateCompanionBuilder =
    BabiesCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      required String id,
      Value<String?> accountId,
      required String name,
      Value<String> gender,
      Value<String?> photo,
      Value<String> status,
      Value<DateTime?> birthDate,
      Value<DateTime?> dueDate,
      Value<DateTime?> lastMenstrualDate,
      Value<int?> gestationalWeeks,
      Value<int> gestationalDays,
      Value<String?> myRole,
      Value<int> memberCount,
      Value<String> settings,
      Value<int> rowid,
    });
typedef $$BabiesTableUpdateCompanionBuilder =
    BabiesCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      Value<String> id,
      Value<String?> accountId,
      Value<String> name,
      Value<String> gender,
      Value<String?> photo,
      Value<String> status,
      Value<DateTime?> birthDate,
      Value<DateTime?> dueDate,
      Value<DateTime?> lastMenstrualDate,
      Value<int?> gestationalWeeks,
      Value<int> gestationalDays,
      Value<String?> myRole,
      Value<int> memberCount,
      Value<String> settings,
      Value<int> rowid,
    });

class $$BabiesTableFilterComposer
    extends Composer<_$AppDatabase, $BabiesTable> {
  $$BabiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photo => $composableBuilder(
    column: $table.photo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastMenstrualDate => $composableBuilder(
    column: $table.lastMenstrualDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gestationalWeeks => $composableBuilder(
    column: $table.gestationalWeeks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gestationalDays => $composableBuilder(
    column: $table.gestationalDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get myRole => $composableBuilder(
    column: $table.myRole,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get settings => $composableBuilder(
    column: $table.settings,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BabiesTableOrderingComposer
    extends Composer<_$AppDatabase, $BabiesTable> {
  $$BabiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photo => $composableBuilder(
    column: $table.photo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastMenstrualDate => $composableBuilder(
    column: $table.lastMenstrualDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gestationalWeeks => $composableBuilder(
    column: $table.gestationalWeeks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gestationalDays => $composableBuilder(
    column: $table.gestationalDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get myRole => $composableBuilder(
    column: $table.myRole,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get settings => $composableBuilder(
    column: $table.settings,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BabiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BabiesTable> {
  $$BabiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<String> get photo =>
      $composableBuilder(column: $table.photo, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get birthDate =>
      $composableBuilder(column: $table.birthDate, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<DateTime> get lastMenstrualDate => $composableBuilder(
    column: $table.lastMenstrualDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get gestationalWeeks => $composableBuilder(
    column: $table.gestationalWeeks,
    builder: (column) => column,
  );

  GeneratedColumn<int> get gestationalDays => $composableBuilder(
    column: $table.gestationalDays,
    builder: (column) => column,
  );

  GeneratedColumn<String> get myRole =>
      $composableBuilder(column: $table.myRole, builder: (column) => column);

  GeneratedColumn<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get settings =>
      $composableBuilder(column: $table.settings, builder: (column) => column);
}

class $$BabiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BabiesTable,
          BabyRow,
          $$BabiesTableFilterComposer,
          $$BabiesTableOrderingComposer,
          $$BabiesTableAnnotationComposer,
          $$BabiesTableCreateCompanionBuilder,
          $$BabiesTableUpdateCompanionBuilder,
          (BabyRow, BaseReferences<_$AppDatabase, $BabiesTable, BabyRow>),
          BabyRow,
          PrefetchHooks Function()
        > {
  $$BabiesTableTableManager(_$AppDatabase db, $BabiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BabiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BabiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BabiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<String?> photo = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> birthDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<DateTime?> lastMenstrualDate = const Value.absent(),
                Value<int?> gestationalWeeks = const Value.absent(),
                Value<int> gestationalDays = const Value.absent(),
                Value<String?> myRole = const Value.absent(),
                Value<int> memberCount = const Value.absent(),
                Value<String> settings = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BabiesCompanion(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                accountId: accountId,
                name: name,
                gender: gender,
                photo: photo,
                status: status,
                birthDate: birthDate,
                dueDate: dueDate,
                lastMenstrualDate: lastMenstrualDate,
                gestationalWeeks: gestationalWeeks,
                gestationalDays: gestationalDays,
                myRole: myRole,
                memberCount: memberCount,
                settings: settings,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                required String id,
                Value<String?> accountId = const Value.absent(),
                required String name,
                Value<String> gender = const Value.absent(),
                Value<String?> photo = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> birthDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<DateTime?> lastMenstrualDate = const Value.absent(),
                Value<int?> gestationalWeeks = const Value.absent(),
                Value<int> gestationalDays = const Value.absent(),
                Value<String?> myRole = const Value.absent(),
                Value<int> memberCount = const Value.absent(),
                Value<String> settings = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BabiesCompanion.insert(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                accountId: accountId,
                name: name,
                gender: gender,
                photo: photo,
                status: status,
                birthDate: birthDate,
                dueDate: dueDate,
                lastMenstrualDate: lastMenstrualDate,
                gestationalWeeks: gestationalWeeks,
                gestationalDays: gestationalDays,
                myRole: myRole,
                memberCount: memberCount,
                settings: settings,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BabiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BabiesTable,
      BabyRow,
      $$BabiesTableFilterComposer,
      $$BabiesTableOrderingComposer,
      $$BabiesTableAnnotationComposer,
      $$BabiesTableCreateCompanionBuilder,
      $$BabiesTableUpdateCompanionBuilder,
      (BabyRow, BaseReferences<_$AppDatabase, $BabiesTable, BabyRow>),
      BabyRow,
      PrefetchHooks Function()
    >;
typedef $$MemoriesTableCreateCompanionBuilder =
    MemoriesCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      required String id,
      required String baby,
      required DateTime date,
      Value<String> title,
      Value<String> note,
      Value<String?> photo,
      Value<String?> localPhotoPath,
      Value<String> firstTag,
      Value<String?> createdBy,
      Value<int> rowid,
    });
typedef $$MemoriesTableUpdateCompanionBuilder =
    MemoriesCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      Value<String> id,
      Value<String> baby,
      Value<DateTime> date,
      Value<String> title,
      Value<String> note,
      Value<String?> photo,
      Value<String?> localPhotoPath,
      Value<String> firstTag,
      Value<String?> createdBy,
      Value<int> rowid,
    });

class $$MemoriesTableFilterComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photo => $composableBuilder(
    column: $table.photo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPhotoPath => $composableBuilder(
    column: $table.localPhotoPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstTag => $composableBuilder(
    column: $table.firstTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photo => $composableBuilder(
    column: $table.photo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPhotoPath => $composableBuilder(
    column: $table.localPhotoPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstTag => $composableBuilder(
    column: $table.firstTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemoriesTable> {
  $$MemoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baby =>
      $composableBuilder(column: $table.baby, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get photo =>
      $composableBuilder(column: $table.photo, builder: (column) => column);

  GeneratedColumn<String> get localPhotoPath => $composableBuilder(
    column: $table.localPhotoPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstTag =>
      $composableBuilder(column: $table.firstTag, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);
}

class $$MemoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemoriesTable,
          MemoryRow,
          $$MemoriesTableFilterComposer,
          $$MemoriesTableOrderingComposer,
          $$MemoriesTableAnnotationComposer,
          $$MemoriesTableCreateCompanionBuilder,
          $$MemoriesTableUpdateCompanionBuilder,
          (MemoryRow, BaseReferences<_$AppDatabase, $MemoriesTable, MemoryRow>),
          MemoryRow,
          PrefetchHooks Function()
        > {
  $$MemoriesTableTableManager(_$AppDatabase db, $MemoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> baby = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> photo = const Value.absent(),
                Value<String?> localPhotoPath = const Value.absent(),
                Value<String> firstTag = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoriesCompanion(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                baby: baby,
                date: date,
                title: title,
                note: note,
                photo: photo,
                localPhotoPath: localPhotoPath,
                firstTag: firstTag,
                createdBy: createdBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                required String id,
                required String baby,
                required DateTime date,
                Value<String> title = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> photo = const Value.absent(),
                Value<String?> localPhotoPath = const Value.absent(),
                Value<String> firstTag = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoriesCompanion.insert(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                baby: baby,
                date: date,
                title: title,
                note: note,
                photo: photo,
                localPhotoPath: localPhotoPath,
                firstTag: firstTag,
                createdBy: createdBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemoriesTable,
      MemoryRow,
      $$MemoriesTableFilterComposer,
      $$MemoriesTableOrderingComposer,
      $$MemoriesTableAnnotationComposer,
      $$MemoriesTableCreateCompanionBuilder,
      $$MemoriesTableUpdateCompanionBuilder,
      (MemoryRow, BaseReferences<_$AppDatabase, $MemoriesTable, MemoryRow>),
      MemoryRow,
      PrefetchHooks Function()
    >;
typedef $$MomEntriesTableCreateCompanionBuilder =
    MomEntriesCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      required String id,
      required String baby,
      required String kind,
      required DateTime date,
      Value<double?> weightKg,
      Value<String?> title,
      Value<String?> note,
      Value<String?> createdBy,
      Value<int> rowid,
    });
typedef $$MomEntriesTableUpdateCompanionBuilder =
    MomEntriesCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      Value<String> id,
      Value<String> baby,
      Value<String> kind,
      Value<DateTime> date,
      Value<double?> weightKg,
      Value<String?> title,
      Value<String?> note,
      Value<String?> createdBy,
      Value<int> rowid,
    });

class $$MomEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $MomEntriesTable> {
  $$MomEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weightKg => $composableBuilder(
    column: $table.weightKg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MomEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MomEntriesTable> {
  $$MomEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weightKg => $composableBuilder(
    column: $table.weightKg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MomEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MomEntriesTable> {
  $$MomEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baby =>
      $composableBuilder(column: $table.baby, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<double> get weightKg =>
      $composableBuilder(column: $table.weightKg, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);
}

class $$MomEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MomEntriesTable,
          MomEntryRow,
          $$MomEntriesTableFilterComposer,
          $$MomEntriesTableOrderingComposer,
          $$MomEntriesTableAnnotationComposer,
          $$MomEntriesTableCreateCompanionBuilder,
          $$MomEntriesTableUpdateCompanionBuilder,
          (
            MomEntryRow,
            BaseReferences<_$AppDatabase, $MomEntriesTable, MomEntryRow>,
          ),
          MomEntryRow,
          PrefetchHooks Function()
        > {
  $$MomEntriesTableTableManager(_$AppDatabase db, $MomEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MomEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MomEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MomEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> baby = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<double?> weightKg = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MomEntriesCompanion(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                baby: baby,
                kind: kind,
                date: date,
                weightKg: weightKg,
                title: title,
                note: note,
                createdBy: createdBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                required String id,
                required String baby,
                required String kind,
                required DateTime date,
                Value<double?> weightKg = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MomEntriesCompanion.insert(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                baby: baby,
                kind: kind,
                date: date,
                weightKg: weightKg,
                title: title,
                note: note,
                createdBy: createdBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MomEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MomEntriesTable,
      MomEntryRow,
      $$MomEntriesTableFilterComposer,
      $$MomEntriesTableOrderingComposer,
      $$MomEntriesTableAnnotationComposer,
      $$MomEntriesTableCreateCompanionBuilder,
      $$MomEntriesTableUpdateCompanionBuilder,
      (
        MomEntryRow,
        BaseReferences<_$AppDatabase, $MomEntriesTable, MomEntryRow>,
      ),
      MomEntryRow,
      PrefetchHooks Function()
    >;
typedef $$CycleSettingsTableTableCreateCompanionBuilder =
    CycleSettingsTableCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      Value<String> id,
      Value<String?> baby,
      Value<DateTime?> birthDate,
      Value<String?> breastfeeding,
      Value<DateTime?> firstPeriodDate,
      Value<String> reminders,
      Value<bool> showFertilityWarning,
      Value<bool> enabled,
      Value<int?> expectedCycleLength,
      Value<int?> periodLength,
      Value<int?> lutealPhaseLength,
      Value<bool> smartPrediction,
      Value<bool> weekStartsSunday,
      Value<int> rowid,
    });
typedef $$CycleSettingsTableTableUpdateCompanionBuilder =
    CycleSettingsTableCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      Value<String> id,
      Value<String?> baby,
      Value<DateTime?> birthDate,
      Value<String?> breastfeeding,
      Value<DateTime?> firstPeriodDate,
      Value<String> reminders,
      Value<bool> showFertilityWarning,
      Value<bool> enabled,
      Value<int?> expectedCycleLength,
      Value<int?> periodLength,
      Value<int?> lutealPhaseLength,
      Value<bool> smartPrediction,
      Value<bool> weekStartsSunday,
      Value<int> rowid,
    });

class $$CycleSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $CycleSettingsTableTable> {
  $$CycleSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get breastfeeding => $composableBuilder(
    column: $table.breastfeeding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstPeriodDate => $composableBuilder(
    column: $table.firstPeriodDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reminders => $composableBuilder(
    column: $table.reminders,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get showFertilityWarning => $composableBuilder(
    column: $table.showFertilityWarning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedCycleLength => $composableBuilder(
    column: $table.expectedCycleLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get periodLength => $composableBuilder(
    column: $table.periodLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lutealPhaseLength => $composableBuilder(
    column: $table.lutealPhaseLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get smartPrediction => $composableBuilder(
    column: $table.smartPrediction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get weekStartsSunday => $composableBuilder(
    column: $table.weekStartsSunday,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CycleSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CycleSettingsTableTable> {
  $$CycleSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get breastfeeding => $composableBuilder(
    column: $table.breastfeeding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstPeriodDate => $composableBuilder(
    column: $table.firstPeriodDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reminders => $composableBuilder(
    column: $table.reminders,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showFertilityWarning => $composableBuilder(
    column: $table.showFertilityWarning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedCycleLength => $composableBuilder(
    column: $table.expectedCycleLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get periodLength => $composableBuilder(
    column: $table.periodLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lutealPhaseLength => $composableBuilder(
    column: $table.lutealPhaseLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get smartPrediction => $composableBuilder(
    column: $table.smartPrediction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get weekStartsSunday => $composableBuilder(
    column: $table.weekStartsSunday,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CycleSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CycleSettingsTableTable> {
  $$CycleSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baby =>
      $composableBuilder(column: $table.baby, builder: (column) => column);

  GeneratedColumn<DateTime> get birthDate =>
      $composableBuilder(column: $table.birthDate, builder: (column) => column);

  GeneratedColumn<String> get breastfeeding => $composableBuilder(
    column: $table.breastfeeding,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firstPeriodDate => $composableBuilder(
    column: $table.firstPeriodDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reminders =>
      $composableBuilder(column: $table.reminders, builder: (column) => column);

  GeneratedColumn<bool> get showFertilityWarning => $composableBuilder(
    column: $table.showFertilityWarning,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get expectedCycleLength => $composableBuilder(
    column: $table.expectedCycleLength,
    builder: (column) => column,
  );

  GeneratedColumn<int> get periodLength => $composableBuilder(
    column: $table.periodLength,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lutealPhaseLength => $composableBuilder(
    column: $table.lutealPhaseLength,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get smartPrediction => $composableBuilder(
    column: $table.smartPrediction,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get weekStartsSunday => $composableBuilder(
    column: $table.weekStartsSunday,
    builder: (column) => column,
  );
}

class $$CycleSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CycleSettingsTableTable,
          CycleSettingsRow,
          $$CycleSettingsTableTableFilterComposer,
          $$CycleSettingsTableTableOrderingComposer,
          $$CycleSettingsTableTableAnnotationComposer,
          $$CycleSettingsTableTableCreateCompanionBuilder,
          $$CycleSettingsTableTableUpdateCompanionBuilder,
          (
            CycleSettingsRow,
            BaseReferences<
              _$AppDatabase,
              $CycleSettingsTableTable,
              CycleSettingsRow
            >,
          ),
          CycleSettingsRow,
          PrefetchHooks Function()
        > {
  $$CycleSettingsTableTableTableManager(
    _$AppDatabase db,
    $CycleSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CycleSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CycleSettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CycleSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> baby = const Value.absent(),
                Value<DateTime?> birthDate = const Value.absent(),
                Value<String?> breastfeeding = const Value.absent(),
                Value<DateTime?> firstPeriodDate = const Value.absent(),
                Value<String> reminders = const Value.absent(),
                Value<bool> showFertilityWarning = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int?> expectedCycleLength = const Value.absent(),
                Value<int?> periodLength = const Value.absent(),
                Value<int?> lutealPhaseLength = const Value.absent(),
                Value<bool> smartPrediction = const Value.absent(),
                Value<bool> weekStartsSunday = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CycleSettingsTableCompanion(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                baby: baby,
                birthDate: birthDate,
                breastfeeding: breastfeeding,
                firstPeriodDate: firstPeriodDate,
                reminders: reminders,
                showFertilityWarning: showFertilityWarning,
                enabled: enabled,
                expectedCycleLength: expectedCycleLength,
                periodLength: periodLength,
                lutealPhaseLength: lutealPhaseLength,
                smartPrediction: smartPrediction,
                weekStartsSunday: weekStartsSunday,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> baby = const Value.absent(),
                Value<DateTime?> birthDate = const Value.absent(),
                Value<String?> breastfeeding = const Value.absent(),
                Value<DateTime?> firstPeriodDate = const Value.absent(),
                Value<String> reminders = const Value.absent(),
                Value<bool> showFertilityWarning = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int?> expectedCycleLength = const Value.absent(),
                Value<int?> periodLength = const Value.absent(),
                Value<int?> lutealPhaseLength = const Value.absent(),
                Value<bool> smartPrediction = const Value.absent(),
                Value<bool> weekStartsSunday = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CycleSettingsTableCompanion.insert(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                baby: baby,
                birthDate: birthDate,
                breastfeeding: breastfeeding,
                firstPeriodDate: firstPeriodDate,
                reminders: reminders,
                showFertilityWarning: showFertilityWarning,
                enabled: enabled,
                expectedCycleLength: expectedCycleLength,
                periodLength: periodLength,
                lutealPhaseLength: lutealPhaseLength,
                smartPrediction: smartPrediction,
                weekStartsSunday: weekStartsSunday,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CycleSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CycleSettingsTableTable,
      CycleSettingsRow,
      $$CycleSettingsTableTableFilterComposer,
      $$CycleSettingsTableTableOrderingComposer,
      $$CycleSettingsTableTableAnnotationComposer,
      $$CycleSettingsTableTableCreateCompanionBuilder,
      $$CycleSettingsTableTableUpdateCompanionBuilder,
      (
        CycleSettingsRow,
        BaseReferences<
          _$AppDatabase,
          $CycleSettingsTableTable,
          CycleSettingsRow
        >,
      ),
      CycleSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$CycleEntriesTableCreateCompanionBuilder =
    CycleEntriesCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      required String id,
      Value<String?> accountId,
      required DateTime date,
      Value<String?> flow,
      Value<String?> lochiaColor,
      Value<String> symptoms,
      Value<int?> mood,
      Value<String?> note,
      Value<int> rowid,
    });
typedef $$CycleEntriesTableUpdateCompanionBuilder =
    CycleEntriesCompanion Function({
      Value<bool> isDeleted,
      Value<DateTime?> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<bool> dirty,
      Value<String> id,
      Value<String?> accountId,
      Value<DateTime> date,
      Value<String?> flow,
      Value<String?> lochiaColor,
      Value<String> symptoms,
      Value<int?> mood,
      Value<String?> note,
      Value<int> rowid,
    });

class $$CycleEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CycleEntriesTable> {
  $$CycleEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lochiaColor => $composableBuilder(
    column: $table.lochiaColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get symptoms => $composableBuilder(
    column: $table.symptoms,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CycleEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CycleEntriesTable> {
  $$CycleEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lochiaColor => $composableBuilder(
    column: $table.lochiaColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symptoms => $composableBuilder(
    column: $table.symptoms,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CycleEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CycleEntriesTable> {
  $$CycleEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get flow =>
      $composableBuilder(column: $table.flow, builder: (column) => column);

  GeneratedColumn<String> get lochiaColor => $composableBuilder(
    column: $table.lochiaColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get symptoms =>
      $composableBuilder(column: $table.symptoms, builder: (column) => column);

  GeneratedColumn<int> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$CycleEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CycleEntriesTable,
          CycleEntryRow,
          $$CycleEntriesTableFilterComposer,
          $$CycleEntriesTableOrderingComposer,
          $$CycleEntriesTableAnnotationComposer,
          $$CycleEntriesTableCreateCompanionBuilder,
          $$CycleEntriesTableUpdateCompanionBuilder,
          (
            CycleEntryRow,
            BaseReferences<_$AppDatabase, $CycleEntriesTable, CycleEntryRow>,
          ),
          CycleEntryRow,
          PrefetchHooks Function()
        > {
  $$CycleEntriesTableTableManager(_$AppDatabase db, $CycleEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CycleEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CycleEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CycleEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> accountId = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String?> flow = const Value.absent(),
                Value<String?> lochiaColor = const Value.absent(),
                Value<String> symptoms = const Value.absent(),
                Value<int?> mood = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CycleEntriesCompanion(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                accountId: accountId,
                date: date,
                flow: flow,
                lochiaColor: lochiaColor,
                symptoms: symptoms,
                mood: mood,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime?> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                required String id,
                Value<String?> accountId = const Value.absent(),
                required DateTime date,
                Value<String?> flow = const Value.absent(),
                Value<String?> lochiaColor = const Value.absent(),
                Value<String> symptoms = const Value.absent(),
                Value<int?> mood = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CycleEntriesCompanion.insert(
                isDeleted: isDeleted,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                dirty: dirty,
                id: id,
                accountId: accountId,
                date: date,
                flow: flow,
                lochiaColor: lochiaColor,
                symptoms: symptoms,
                mood: mood,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CycleEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CycleEntriesTable,
      CycleEntryRow,
      $$CycleEntriesTableFilterComposer,
      $$CycleEntriesTableOrderingComposer,
      $$CycleEntriesTableAnnotationComposer,
      $$CycleEntriesTableCreateCompanionBuilder,
      $$CycleEntriesTableUpdateCompanionBuilder,
      (
        CycleEntryRow,
        BaseReferences<_$AppDatabase, $CycleEntriesTable, CycleEntryRow>,
      ),
      CycleEntryRow,
      PrefetchHooks Function()
    >;
typedef $$SyncCursorsTableCreateCompanionBuilder =
    SyncCursorsCompanion Function({
      required String baby,
      Value<String?> cursor,
      Value<int> rowid,
    });
typedef $$SyncCursorsTableUpdateCompanionBuilder =
    SyncCursorsCompanion Function({
      Value<String> baby,
      Value<String?> cursor,
      Value<int> rowid,
    });

class $$SyncCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get baby =>
      $composableBuilder(column: $table.baby, builder: (column) => column);

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);
}

class $$SyncCursorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCursorsTable,
          SyncCursor,
          $$SyncCursorsTableFilterComposer,
          $$SyncCursorsTableOrderingComposer,
          $$SyncCursorsTableAnnotationComposer,
          $$SyncCursorsTableCreateCompanionBuilder,
          $$SyncCursorsTableUpdateCompanionBuilder,
          (
            SyncCursor,
            BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>,
          ),
          SyncCursor,
          PrefetchHooks Function()
        > {
  $$SyncCursorsTableTableManager(_$AppDatabase db, $SyncCursorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> baby = const Value.absent(),
                Value<String?> cursor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion(
                baby: baby,
                cursor: cursor,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String baby,
                Value<String?> cursor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion.insert(
                baby: baby,
                cursor: cursor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCursorsTable,
      SyncCursor,
      $$SyncCursorsTableFilterComposer,
      $$SyncCursorsTableOrderingComposer,
      $$SyncCursorsTableAnnotationComposer,
      $$SyncCursorsTableCreateCompanionBuilder,
      $$SyncCursorsTableUpdateCompanionBuilder,
      (
        SyncCursor,
        BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>,
      ),
      SyncCursor,
      PrefetchHooks Function()
    >;
typedef $$HealthStatusesTableCreateCompanionBuilder =
    HealthStatusesCompanion Function({
      required String baby,
      required String kind,
      required String itemKey,
      Value<bool> done,
      Value<DateTime?> statusDate,
      Value<int> rowid,
    });
typedef $$HealthStatusesTableUpdateCompanionBuilder =
    HealthStatusesCompanion Function({
      Value<String> baby,
      Value<String> kind,
      Value<String> itemKey,
      Value<bool> done,
      Value<DateTime?> statusDate,
      Value<int> rowid,
    });

class $$HealthStatusesTableFilterComposer
    extends Composer<_$AppDatabase, $HealthStatusesTable> {
  $$HealthStatusesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get statusDate => $composableBuilder(
    column: $table.statusDate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HealthStatusesTableOrderingComposer
    extends Composer<_$AppDatabase, $HealthStatusesTable> {
  $$HealthStatusesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemKey => $composableBuilder(
    column: $table.itemKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get statusDate => $composableBuilder(
    column: $table.statusDate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HealthStatusesTableAnnotationComposer
    extends Composer<_$AppDatabase, $HealthStatusesTable> {
  $$HealthStatusesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get baby =>
      $composableBuilder(column: $table.baby, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get itemKey =>
      $composableBuilder(column: $table.itemKey, builder: (column) => column);

  GeneratedColumn<bool> get done =>
      $composableBuilder(column: $table.done, builder: (column) => column);

  GeneratedColumn<DateTime> get statusDate => $composableBuilder(
    column: $table.statusDate,
    builder: (column) => column,
  );
}

class $$HealthStatusesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HealthStatusesTable,
          HealthStatusRow,
          $$HealthStatusesTableFilterComposer,
          $$HealthStatusesTableOrderingComposer,
          $$HealthStatusesTableAnnotationComposer,
          $$HealthStatusesTableCreateCompanionBuilder,
          $$HealthStatusesTableUpdateCompanionBuilder,
          (
            HealthStatusRow,
            BaseReferences<
              _$AppDatabase,
              $HealthStatusesTable,
              HealthStatusRow
            >,
          ),
          HealthStatusRow,
          PrefetchHooks Function()
        > {
  $$HealthStatusesTableTableManager(
    _$AppDatabase db,
    $HealthStatusesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HealthStatusesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HealthStatusesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HealthStatusesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> baby = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> itemKey = const Value.absent(),
                Value<bool> done = const Value.absent(),
                Value<DateTime?> statusDate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HealthStatusesCompanion(
                baby: baby,
                kind: kind,
                itemKey: itemKey,
                done: done,
                statusDate: statusDate,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String baby,
                required String kind,
                required String itemKey,
                Value<bool> done = const Value.absent(),
                Value<DateTime?> statusDate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HealthStatusesCompanion.insert(
                baby: baby,
                kind: kind,
                itemKey: itemKey,
                done: done,
                statusDate: statusDate,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HealthStatusesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HealthStatusesTable,
      HealthStatusRow,
      $$HealthStatusesTableFilterComposer,
      $$HealthStatusesTableOrderingComposer,
      $$HealthStatusesTableAnnotationComposer,
      $$HealthStatusesTableCreateCompanionBuilder,
      $$HealthStatusesTableUpdateCompanionBuilder,
      (
        HealthStatusRow,
        BaseReferences<_$AppDatabase, $HealthStatusesTable, HealthStatusRow>,
      ),
      HealthStatusRow,
      PrefetchHooks Function()
    >;
typedef $$LocalRemindersTableCreateCompanionBuilder =
    LocalRemindersCompanion Function({
      Value<int> localId,
      required String baby,
      Value<String> type,
      Value<String> scheduleJson,
      Value<bool> enabled,
      Value<DateTime?> createdAt,
    });
typedef $$LocalRemindersTableUpdateCompanionBuilder =
    LocalRemindersCompanion Function({
      Value<int> localId,
      Value<String> baby,
      Value<String> type,
      Value<String> scheduleJson,
      Value<bool> enabled,
      Value<DateTime?> createdAt,
    });

class $$LocalRemindersTableFilterComposer
    extends Composer<_$AppDatabase, $LocalRemindersTable> {
  $$LocalRemindersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleJson => $composableBuilder(
    column: $table.scheduleJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalRemindersTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalRemindersTable> {
  $$LocalRemindersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baby => $composableBuilder(
    column: $table.baby,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleJson => $composableBuilder(
    column: $table.scheduleJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalRemindersTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalRemindersTable> {
  $$LocalRemindersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get baby =>
      $composableBuilder(column: $table.baby, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get scheduleJson => $composableBuilder(
    column: $table.scheduleJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LocalRemindersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalRemindersTable,
          ReminderRow,
          $$LocalRemindersTableFilterComposer,
          $$LocalRemindersTableOrderingComposer,
          $$LocalRemindersTableAnnotationComposer,
          $$LocalRemindersTableCreateCompanionBuilder,
          $$LocalRemindersTableUpdateCompanionBuilder,
          (
            ReminderRow,
            BaseReferences<_$AppDatabase, $LocalRemindersTable, ReminderRow>,
          ),
          ReminderRow,
          PrefetchHooks Function()
        > {
  $$LocalRemindersTableTableManager(
    _$AppDatabase db,
    $LocalRemindersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRemindersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRemindersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRemindersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> localId = const Value.absent(),
                Value<String> baby = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> scheduleJson = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
              }) => LocalRemindersCompanion(
                localId: localId,
                baby: baby,
                type: type,
                scheduleJson: scheduleJson,
                enabled: enabled,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> localId = const Value.absent(),
                required String baby,
                Value<String> type = const Value.absent(),
                Value<String> scheduleJson = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
              }) => LocalRemindersCompanion.insert(
                localId: localId,
                baby: baby,
                type: type,
                scheduleJson: scheduleJson,
                enabled: enabled,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalRemindersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalRemindersTable,
      ReminderRow,
      $$LocalRemindersTableFilterComposer,
      $$LocalRemindersTableOrderingComposer,
      $$LocalRemindersTableAnnotationComposer,
      $$LocalRemindersTableCreateCompanionBuilder,
      $$LocalRemindersTableUpdateCompanionBuilder,
      (
        ReminderRow,
        BaseReferences<_$AppDatabase, $LocalRemindersTable, ReminderRow>,
      ),
      ReminderRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$RecordsTableTableManager get records =>
      $$RecordsTableTableManager(_db, _db.records);
  $$BabiesTableTableManager get babies =>
      $$BabiesTableTableManager(_db, _db.babies);
  $$MemoriesTableTableManager get memories =>
      $$MemoriesTableTableManager(_db, _db.memories);
  $$MomEntriesTableTableManager get momEntries =>
      $$MomEntriesTableTableManager(_db, _db.momEntries);
  $$CycleSettingsTableTableTableManager get cycleSettingsTable =>
      $$CycleSettingsTableTableTableManager(_db, _db.cycleSettingsTable);
  $$CycleEntriesTableTableManager get cycleEntries =>
      $$CycleEntriesTableTableManager(_db, _db.cycleEntries);
  $$SyncCursorsTableTableManager get syncCursors =>
      $$SyncCursorsTableTableManager(_db, _db.syncCursors);
  $$HealthStatusesTableTableManager get healthStatuses =>
      $$HealthStatusesTableTableManager(_db, _db.healthStatuses);
  $$LocalRemindersTableTableManager get localReminders =>
      $$LocalRemindersTableTableManager(_db, _db.localReminders);
}
