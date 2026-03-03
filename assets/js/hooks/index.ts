// Add external LiveView hooks here and export them.
// Each hook is a plain JS object with lifecycle callbacks (mounted, updated, destroyed, etc.)
//
// Example:
//
//   const MyHook = {
//     mounted() {
//       console.log("MyHook mounted", this.el)
//     }
//   }
//
// Then reference it in your template with:
//   <div id="my-element" phx-hook="MyHook">...</div>
//
// Note: always include a unique DOM id alongside phx-hook.
const DragNDropHook = {
  mounted() {
    this.el.addEventListener("dragover", (event: DragEvent) => {
      event.preventDefault()
      this.el.classList.add("drag-over")
    })

    this.el.addEventListener("dragleave", () => {
      this.el.classList.remove("drag-over")
    })

    this.el.addEventListener("drop", () => {
      this.el.classList.remove("drag-over")
    })
  }
}

const hooks: Record<string, object> = { DragNDropHook }

export default hooks
