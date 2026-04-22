import {
  isActorMissingError,
  jsonResponse,
  notFoundVm,
  userOwnsVm,
  withAuthedVmApiRoute,
} from "../../../../../services/vms/routeHelpers";
import { setSpanAttributes } from "../../../../../services/telemetry";

export const dynamic = "force-dynamic";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
): Promise<Response> {
  return withAuthedVmApiRoute(
    request,
    "/api/vm/[id]/attach-endpoint",
    { "cmux.vm.operation": "open_attach" },
    "/api/vm/[id]/attach-endpoint failed",
    async ({ user, client, span }) => {
      const { id } = await params;
      setSpanAttributes(span, { "cmux.vm.id": id });
      if (!(await userOwnsVm(client, user.id, id))) return notFoundVm(id);
      try {
        const endpoint = await client.vmActor.get([id]).openAttach();
        setSpanAttributes(span, { "cmux.vm.attach.transport": endpoint.transport });
        return jsonResponse(endpoint);
      } catch (err) {
        if (isActorMissingError(err)) {
          setSpanAttributes(span, { "cmux.rivet.actor_missing": true });
          return notFoundVm(id);
        }
        throw err;
      }
    },
  );
}
