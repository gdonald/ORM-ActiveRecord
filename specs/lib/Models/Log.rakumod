use ORM::ActiveRecord::Model;

unit module Models::Log;

class Log is Model is export {}

GLOBAL::<Log> := Log;
