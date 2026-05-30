use ORM::ActiveRecord::Model;

unit module Models::Account;

class Account is Model is export {}

GLOBAL::<Account> := Account;
