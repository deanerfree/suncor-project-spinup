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
const DownloadHook = {
  mounted() {
    this.handleEvent("download", ({ url }) => {
      const link = document.createElement("a")
      link.href = url
      link.download = ""
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
    })
  }
}

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

const LocalStorageHook = {
  mounted() {
    const saved = localStorage.getItem("well_stick")
    console.log("LocalStorageHook mounted, found saved value:", saved)

    if (saved) {
      this.pushEvent("load_result", { data: JSON.parse(saved) })
    }

    this.handleEvent("store_result", ({ key, data, path }) => {
      localStorage.setItem(key, JSON.stringify(data))
      window.location = path
    })
  }
}

const hooks: Record<string, object> = { DragNDropHook, LocalStorageHook, DownloadHook }

export default hooks
