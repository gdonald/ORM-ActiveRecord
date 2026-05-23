
use ORM::ActiveRecord::Schema::Field;

class Validator is export {
  has $.klass;
  has Field $.field;
  has Hash $.params;
}

class EachValidator is export {
  has $.klass;
  has @.fields of Str;
  has Block $.block;
  has Hash $.params;
}

class WithValidator is export {
  has $.klass;
  has $.validator;
  has Hash $.options;
}

class AssociatedValidator is export {
  has $.klass;
  has Str $.name;
  has Hash $.params;
}
