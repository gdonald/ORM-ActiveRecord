use ORM::ActiveRecord::Model;

unit module Defaults::NullableColumns;

class Guardian is Model is export {}

class Ward is Model is export {}

GLOBAL::<Guardian> := Guardian;
GLOBAL::<Ward> := Ward;
