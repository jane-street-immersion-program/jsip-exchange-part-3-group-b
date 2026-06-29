(** Fundamental-price simulation for the JSIP exchange.

    Exposes [Fundamental_oracle], a per-symbol Ornstein-Uhlenbeck process
    that supplies a "true price" trajectory for bots and scenarios to anchor
    against. The exchange itself never reads this — it exists solely to make
    scripted scenarios reproducible and visually interesting. *)

module Fundamental_oracle = Fundamental_oracle
