use ORM::ActiveRecord::Model;

unit module Models::Game;

class Game is Model is export {}

GLOBAL::<Game> := Game;
