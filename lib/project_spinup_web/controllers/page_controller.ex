defmodule ProjectSpinupWeb.PageController do
  use ProjectSpinupWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
