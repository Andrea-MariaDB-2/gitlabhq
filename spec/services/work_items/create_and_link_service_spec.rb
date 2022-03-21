# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::CreateAndLinkService do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:related_work_item) { create(:work_item, project: project) }

  let(:spam_params) { double }
  let(:link_params) { {} }
  let(:params) do
    {
      title: 'Awesome work item',
      description: 'please fix'
    }
  end

  before_all do
    project.add_developer(user)
  end

  describe '#execute' do
    subject(:service_result) { described_class.new(project: project, current_user: user, params: params, spam_params: spam_params, link_params: link_params).execute }

    before do
      stub_spam_services
    end

    context 'when work item params are valid' do
      it { is_expected.to be_success }

      it 'creates a work item successfully with no links' do
        expect do
          service_result
        end.to change(WorkItem, :count).by(1).and(
          not_change(IssueLink, :count)
        )
      end

      context 'when link params are valid' do
        let(:link_params) { { issuable_references: [related_work_item.to_reference] } }

        it 'creates a work item successfully with links' do
          expect do
            service_result
          end.to change(WorkItem, :count).by(1).and(
            change(IssueLink, :count).by(1)
          )
        end
      end

      context 'when link params are invalid' do
        let(:link_params) { { issuable_references: ['invalid reference'] } }

        it { is_expected.to be_error }

        it 'does not create a link and does not rollback transaction' do
          expect do
            service_result
          end.to not_change(IssueLink, :count).and(
            change(WorkItem, :count).by(1)
          )
        end

        it 'returns a link creation error message' do
          expect(service_result.errors).to contain_exactly('No matching issue found. Make sure that you are adding a valid issue URL.')
        end
      end
    end

    context 'when work item params are invalid' do
      let(:params) do
        {
          title: '',
          description: 'invalid work item'
        }
      end

      it { is_expected.to be_error }

      it 'does not create a work item or links' do
        expect do
          service_result
        end.to not_change(WorkItem, :count).and(
          not_change(IssueLink, :count)
        )
      end

      it 'returns work item errors' do
        expect(service_result.errors).to contain_exactly("Title can't be blank")
      end
    end
  end
end
