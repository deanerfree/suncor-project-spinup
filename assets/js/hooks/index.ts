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
    this.files = []
    this.el.addEventListener("dragover", (event) => {
      event.preventDefault()
      this.el.classList.add("drag-over")
    })

    this.el.addEventListener("dragleave", () => {
      this.el.classList.remove("drag-over")
    })

    this.el.addEventListener("drop", (event) => {
      event.preventDefault()
      this.el.classList.remove("drag-over")
      this.files = [...event.dataTransfer.files]
      console.log("Files dropped:", this.files)
    

    })

    const renderFile = (file) => {
      const fileItem = document.createElement("div")
      fileItem.textContent = file.name
      this.querySelector(".file-list").appendChild(fileItem)
    }

    this.el.addEventListener("click", () => {
      this.files.forEach(renderFile)
    })
  }
}

const hooks: Record<string, object> = { DragNDropHook }

export default hooks
