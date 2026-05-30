use ORM::ActiveRecord::Model;

unit module Models::Attachment;

class Attachment is Model is export {
  submethod BUILD {
    self.belongs-to: attachable => %(:polymorphic, :optional);
  }
}

GLOBAL::<Attachment> := Attachment;
