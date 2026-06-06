defmodule SlidexWeb.Components.Timers do
  use SlidexWeb, :html

  attr :datetime, :string, required: true

  def expires_at(assigns) do
    ~H"""
    <time
      id={"datetime-#{System.unique_integer([:positive])}"}
      phx-hook=".RelativeTime"
      data-datetime={@datetime}
    >
      <span class="whitespace-nowrap">{@datetime}</span>
    </time>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".RelativeTime">
      export default {
        mounted() { this.update(); },
        destroyed() { clearTimeout(this.timer); },
        update() {
        const rawDate = this.el.dataset.datetime;
        const diff = (new Date(rawDate) - new Date()) / 1000;

        // Determine the largest unit that makes sense
        let value, unit;
        if (diff > 86400) { value = diff / 86400; unit = 'day'; }
        else if (diff > 3600) { value = diff / 3600; unit = 'hour'; }
        else { value = diff / 60; unit = 'minute'; }

        // This handles the language translation AND grammar automatically
        this.el.innerText = new Intl.RelativeTimeFormat(undefined, { numeric: 'always' })
          .format(Math.round(value), unit);

        this.timer = setTimeout(() => this.update(), diff <= 300 ? 1000 : 60000);
        }
      }
    </script>
    """
  end
end
