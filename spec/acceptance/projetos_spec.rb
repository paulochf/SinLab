require_relative '../spec_helper'

feature "Projetos" do
	include Helpers

	describe "novo" do
		scenario "deveria poder ser criado" do
			admin_faz_login
		  visit projetos_path
		  fill_in "Nome",  :with => "Odin"
		  fill_in "Descrição", :with => "King of Argard"
		  click_button "Salvar"
		  page.should have_content(I18n.t("projetos.create.success", :model => "Projeto"))
		  page.should have_content(@projeto_novo[:nome])
		end

		scenario "nao poderia ser criado por desenvolvedor" do
		  desenvolvedor_faz_login
		  visit projetos_path
		  fill_in "Nome",  :with => @projeto_novo[:nome]
		  fill_in "Descrição", :with => @projeto_novo[:descricao]
		  click_button "Salvar"
		  page.should have_content(I18n.t("unauthorized.manage.all") )
		end
	end

	describe "existente" do
		scenario "deveria poder ser editado" do
		  admin_faz_login
		  visit projetos_path
		  click_link Projeto.first.nome
		  fill_in "Nome", :with => "Teste"
#     save_and_open_page
 		  click_button "Salvar"
		  page.should have_content(I18n.t("projetos.update.success"))
		end

		scenario "nao poderia ser editado por desenvolvedor" do
		  desenvolvedor_faz_login
		  visit projetos_path
 		  page.should have_no_selector(:link_or_button, Projeto.first.nome)
 		  page.should have_content(Projeto.first.nome)
		end

		scenario "não deveria ser acessivel sem login" do
		  visit projetos_path
		  page.should have_content(I18n.t("devise.failure.unauthenticated"))
		end

	end

	before(:each) do
	  @projeto_novo = FactoryGirl.attributes_for(:projeto)
	end
end
