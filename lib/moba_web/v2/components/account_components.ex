defmodule MobaWeb.V2.Components.AccountComponents do
  use Phoenix.Component

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true
  slot :footer

  def account_panel(assigns) do
    ~H"""
    <section id={@id} class="account-pages account-modern" aria-labelledby={"#{@id}-title"}>
      <header class="account-modern-heading">
        <span class="account-crest" aria-hidden="true">◆</span>
        <span class="account-eyebrow">Browser MOBA · Account</span>
        <h1 id={"#{@id}-title"}>{@title}</h1>
        <p :if={@subtitle}>{@subtitle}</p>
      </header>
      <div class="account-modern-body">{render_slot(@inner_block)}</div>
      <footer :if={@footer != []} class="account-modern-footer">{render_slot(@footer)}</footer>
    </section>
    """
  end
end
