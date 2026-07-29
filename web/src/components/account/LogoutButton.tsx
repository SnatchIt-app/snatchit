import { signOutAction } from "@/lib/auth/actions";
import { Button } from "@/components/ui/Button";

export function LogoutButton() {
  return (
    <form action={signOutAction}>
      <Button type="submit" variant="secondary">
        Log out
      </Button>
    </form>
  );
}
