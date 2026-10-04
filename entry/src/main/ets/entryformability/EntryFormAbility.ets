import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DailyPoemWidgetUtil } from '../common/utils/DailyPoemWidgetUtil';
import { CheckInWidgetUtil } from '../common/utils/CheckInWidgetUtil';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId: string = (want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '') as string;
    let formName: string = (want.parameters?.[formInfo.FormParam.NAME_KEY] ?? '') as string;
    let dimension: string = (want.parameters?.[formInfo.FormParam.DIMENSION_KEY] ?? '') as string;
    let formData: formBindingData.FormBindingData;
    if (formName === 'CheckInWidget') {
      if (formId) {
        DailyPoemWidgetUtil.saveFormId(this.context, formId, 'checkin', dimension);
      }
      formData = formBindingData.createFormBindingData(CheckInWidgetUtil.buildCardData(this.context, dimension));
    } else {
      if (formId) {
        DailyPoemWidgetUtil.saveFormId(this.context, formId, 'poem', dimension);
      }
      formData = formBindingData.createFormBindingData(DailyPoemWidgetUtil.buildCardData(this.context, dimension));
    }
    return formData;
  }

  onUpdateForm(formId: string): void {
    let type: string = DailyPoemWidgetUtil.getFormType(this.context, formId);
    let dimension: string = DailyPoemWidgetUtil.getFormDimension(this.context, formId);
    let formData: formBindingData.FormBindingData;
    if (type === 'checkin') {
      formData = formBindingData.createFormBindingData(CheckInWidgetUtil.buildCardData(this.context, dimension));
    } else {
      formData = formBindingData.createFormBindingData(DailyPoemWidgetUtil.buildCardData(this.context, dimension));
    }
    formProvider.updateForm(formId, formData).catch((error: BusinessError) => {
      console.error('[EntryFormAbility] updateForm failed: ' + JSON.stringify(error));
    });
  }

  onRemoveForm(formId: string): void {
    DailyPoemWidgetUtil.removeFormId(this.context, formId);
  }
}
