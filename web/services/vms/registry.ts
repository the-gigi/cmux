import { setup } from "rivetkit";
import { vmActor } from "./actors/vm";
import { userVmsActor } from "./actors/userVms";

export const registry = setup({
  use: { vmActor, userVmsActor },
});

export type Registry = typeof registry;
