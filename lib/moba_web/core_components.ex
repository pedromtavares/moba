defmodule MobaWeb.CoreComponents do
  use Phoenix.Component

  use Gettext, backend: MobaWeb.Gettext

  alias Phoenix.HTML
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "flex items-start gap-3 w-80 sm:w-96 p-4 rounded-lg border shadow-lg",
        "bg-white text-gray-800",
        @kind == :info && "border-blue-300",
        @kind == :error && "border-red-300"
      ]}
      {@rest}
    >
      <div class="flex-1 min-w-0">
        <p :if={@title} class={["font-semibold text-sm", @kind == :info && "text-blue-600", @kind == :error && "text-red-600"]}>
          {@title}
        </p>
        <p class="text-sm break-words"><%= msg %></p>
      </div>
      <button
        type="button"
        class="group shrink-0 cursor-pointer p-1 -m-1 rounded"
        aria-label={gettext("close")}
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form for={@for} as={@as} {@rest}>
      <div class="space-y-4">
        <%= render_slot(@inner_block) %>
      </div>
      <div :for={action <- @actions} class="mt-4 flex items-center justify-between gap-6">
        <%= render_slot(action) %>
      </div>
    </.form>
    """
  end

  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string, default: nil
  attr :variant, :string, default: nil, values: ~w(primary) ++ [nil]
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign_new(assigns, :class, fn ->
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3 text-sm font-semibold leading-6 text-white active:text-white/80"
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        <%= render_slot(@inner_block) %>
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        <%= render_slot(@inner_block) %>
      </button>
      """
    end
  end

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <label class="flex items-center gap-2 text-sm">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "rounded border-zinc-300"}
          {@rest}
        />
        <%= @label %>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label class="block text-sm font-medium text-zinc-700">
        <span :if={@label} class="block mb-1"><%= @label %></span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full border border-zinc-300 rounded-md py-2 px-3 text-sm", @errors != [] && (@error_class || "border-red-500")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value=""><%= @prompt %></option>
          <%= Form.options_for_select(@options, @value) %>
        </select>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label class="block text-sm font-medium text-zinc-700">
        <span :if={@label} class="block mb-1"><%= @label %></span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full border border-zinc-300 rounded-md py-2 px-3 text-sm",
            @errors != [] && (@error_class || "border-red-500")
          ]}
          {@rest}
          ><%= Form.normalize_value("textarea", @value) %></textarea>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="mb-2">
      <label class="block text-sm font-medium text-zinc-700">
        <span :if={@label} class="block mb-1"><%= @label %></span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full border border-zinc-300 rounded-md py-2 px-3 text-sm",
            @errors != [] && (@error_class || "border-red-500")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          <%= render_slot(@inner_block) %>
        </h1>
        <p :if={@subtitle != []} class="text-sm text-zinc-600">
          <%= render_slot(@subtitle) %>
        </p>
      </div>
      <div class="flex-none"><%= render_slot(@actions) %></div>
    </header>
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _rest} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(MobaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(MobaWeb.Gettext, "errors", msg, opts)
    end
  end

  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  def error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-red-600">
      <.icon name="hero-exclamation-circle" class="size-5" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end
end
