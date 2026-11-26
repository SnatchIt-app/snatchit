/** Block repeated form submits, including implicit Enter submits, until the action settles. */
export function createSubmissionGuard() {
  let locked = false;
  return {
    onSubmit(event: { preventDefault(): void }) {
      if (locked) event.preventDefault();
      else locked = true;
    },
    release() {
      locked = false;
    },
  };
}
