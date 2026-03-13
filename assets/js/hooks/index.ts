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
    const key = (this.el as HTMLElement).dataset.key || "well_stick"
    const saved = localStorage.getItem(key)

    if (key === "well_stick") {
      if (saved) {
        this.pushEvent("load_result", { data: JSON.parse(saved) })
      }

      this.handleEvent("store_result", ({ key: k, data, path }) => {
        localStorage.setItem(k, JSON.stringify(data))
        window.location = path
      })
    } else {
      // Form field mode: populate inputs on mount, save on every change
      if (saved) {
        const data = JSON.parse(saved) as Record<string, string>
        Object.entries(data).forEach(([name, value]) => {
          const input = this.el.querySelector(`[name="${name}"]`) as HTMLInputElement | null
          if (input) input.value = value
        })
      }

      this.el.addEventListener("input", () => {
        const data: Record<string, string> = {}
        Array.from((this.el as HTMLElement).querySelectorAll("input[name], select[name], textarea[name]")).forEach((el) => {
          const input = el as HTMLInputElement
          data[input.name] = input.value
        })
        localStorage.setItem(key, JSON.stringify(data))
      })
    }
  }
}

const PhoneInputHook = {
  mounted() {
    this.el.addEventListener("input", (e: Event) => {
      const input = e.target as HTMLInputElement
      const digits = input.value.replace(/\D/g, "").slice(0, 10)
      let formatted = digits
      if (digits.length > 6) {
        formatted = digits.slice(0, 3) + "-" + digits.slice(3, 6) + "-" + digits.slice(6)
      } else if (digits.length > 3) {
        formatted = digits.slice(0, 3) + "-" + digits.slice(3)
      }
      input.value = formatted
    })
  }
}

const hooks = { DragNDropHook, LocalStorageHook, DownloadHook, PhoneInputHook }

export default hooks
